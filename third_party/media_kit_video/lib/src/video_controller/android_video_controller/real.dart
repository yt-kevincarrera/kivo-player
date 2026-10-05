/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/utils/query_decoders.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';
// Kivo patch (KIVO_PATCHES.md).
import 'package:media_kit_video/src/kivo_surface.dart';

/// {@template android_video_controller}
///
/// AndroidVideoController
/// ----------------------
///
/// The [PlatformVideoController] implementation based on native JNI & C/C++ used on Android.
///
/// {@endtemplate}
class AndroidVideoController extends PlatformVideoController {
  /// Whether [AndroidVideoController] is supported on the current platform or not.
  static bool get supported => Platform.isAndroid;

  /// Pointer address to the global object reference of `android.view.Surface` i.e. `(intptr_t)(*android.view.Surface)`.
  final ValueNotifier<int?> wid = ValueNotifier<int?>(null);

  /// [Lock] used to synchronize [onLoadHooks], [onUnloadHooks] & [subscription].
  final lock = Lock();

  NativePlayer get platform => player.platform as NativePlayer;

  Future<void> setProperty(String key, String value) async {
    await platform.setProperty(key, value, waitForInitialization: false);
  }

  Future<void> setProperties(Map<String, String> properties) async {
    for (final entry in properties.entries) {
      await setProperty(entry.key, entry.value);
    }
  }

  // ---- Kivo patch (KIVO_PATCHES.md) ------------------------------------
  // The render surface is NOT re-sized to each video as upstream does: every
  // resize hands mpv a new surface and re-creates its video output (measured
  // on a Pixel 6: 130–185 ms of black plus a stream refresh, the audio held).
  // It starts at 16:9 of the screen's short side (1920x1080 on a 1080p-wide
  // screen: 16:9 video maps 1:1), and only grows — never shrinks — when a
  // video will be SHOWN bigger than it (in practice: a portrait video, once).
  // mpv stretches each video over the whole surface (keepaspect=no) and
  // [rect] keeps the video's own size, so Flutter lays the texture out at the
  // video's aspect ratio, undoing the stretch.
  int _surfaceW = 0;
  int _surfaceH = 0;

  /// The current video's size, once known (what [rect] must show).
  Rect? _kivoVideoRect;

  /// A new surface arrived (Resize with wid != 0) since the last resize.
  bool _kivoNewSurface = false;

  /// What mpv's blend-subtitles holds (written only on change).
  String? _kivoBlend;

  /// The physical DISPLAY (not the window: PiP or split-screen must not
  /// shrink anything), long side x short side; null if unknown.
  static _KivoSize? _display() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return null;
    Size size;
    try {
      size = views.first.display.size;
    } catch (_) {
      size = views.first.physicalSize;
    }
    final long = size.longestSide.round(), short = size.shortestSide.round();
    if (long <= 0 || short <= 0) return null;
    return _KivoSize(long, short);
  }

  /// The surface a video of [w]x[h] needs: at least the 16:9 base, at least
  /// what this video is shown at on this screen (fitted, in the orientation
  /// that suits it, never more than its own pixels), never less than now.
  _KivoSize _kivoTarget(int w, int h) {
    final d = _display();
    if (d == null) {
      return _KivoSize(math.max(_surfaceW, w), math.max(_surfaceH, h));
    }
    // d.a = long side, d.b = short side.
    final baseW = (d.b * 16 / 9).round(), baseH = d.b;
    var needW = 0, needH = 0;
    if (w > 0 && h > 0) {
      final boxW = w >= h ? d.a : d.b;
      final boxH = w >= h ? d.b : d.a;
      final scale = math.min(1.0, math.min(boxW / w, boxH / h));
      needW = (w * scale).round();
      needH = (h * scale).round();
    }
    return _KivoSize(
      math.max(math.max(_surfaceW, baseW), needW),
      math.max(math.max(_surfaceH, baseH), needH),
    );
  }

  /// Makes sure the surface is at least [_kivoTarget] (a new surface →
  /// [widListener] re-creates --vo). Call under [lock].
  Future<void> _kivoEnsure(int videoW, int videoH) async {
    final t = _kivoTarget(videoW, videoH);
    if (t.a == _surfaceW && t.b == _surfaceH) return;
    kivoSurfaceBusy.value = true;
    _kivoNewSurface = false;
    kivoTrace?.call('media_kit surface resize to ${t.a}x${t.b}');
    _surfaceW = t.a;
    _surfaceH = t.b;
    final handle = await player.handle;
    await _channel.invokeMethod(
      'VideoOutputManager.SetSurfaceSize',
      {
        'handle': handle.toString(),
        'width': t.a.toString(),
        'height': t.b.toString(),
      },
    );
    // The native side may find nothing to change (no new surface, so no
    // widListener): only then is "busy" cleared by time.
    final w = t.a, h = t.b;
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (kivoSurfaceBusy.value &&
          !_kivoNewSurface &&
          _surfaceW == w &&
          _surfaceH == h) {
        kivoSurfaceBusy.value = false;
      }
    });
  }

  /// Subtitles mpv draws (PGS, ASS) are drawn undistorted on the surface;
  /// when the video is stretched to fill it, Flutter's un-stretch would
  /// squeeze them. Then they are blended into the video instead (stretched
  /// and restored with it). A video with the surface's own shape needs
  /// neither — and keeps them sharp.
  Future<void> _kivoBlendFor(int w, int h) async {
    if (_surfaceW <= 0 || _surfaceH <= 0) return;
    final stretch = (w / h) / (_surfaceW / _surfaceH);
    final blend = (stretch - 1).abs() < 0.02 ? 'no' : 'video';
    if (blend == _kivoBlend) return;
    _kivoBlend = blend;
    await setProperty('blend-subtitles', blend);
  }

  /// Sizes the surface before any video, so the first one plays with no
  /// resize at all.
  Future<void> _kivoPresize() =>
      lock.synchronized(() => _kivoEnsure(0, 0));
  // ---- end Kivo patch --------------------------------------------------

  /// Listener for updating the --wid property.
  Future<void> widListener() {
    return lock.synchronized(() async {
      // Kivo patch: the surface's size, not the video's (see above).
      final width = _surfaceW > 0 ? _surfaceW : (rect.value?.width.toInt() ?? 1);
      final height = _surfaceH > 0 ? _surfaceH : (rect.value?.height.toInt() ?? 1);
      final androidSurfaceSizeValue = [width, height].join('x');
      final widValue = wid.value?.toString() ?? '0';
      // When --wid is 0, vo=null is required to avoid SIGSEGV.
      final voValue = widValue == '0' ? 'null' : configuration.vo!;
      final vidValue = widValue == '0' ? 'no' : 'auto';
      kivoTrace?.call('media_kit vo re-init on wid=$widValue ${width}x$height');
      // It is important to re-initialize --vo after --android-surface-size.
      await setProperty('vo', 'null');
      await setProperties(
        {
          // ORDER IS IMPORTANT.
          'android-surface-size': androidSurfaceSizeValue,
          'wid': widValue,
          'vo': voValue,
          // It is important to re-initialize --vid in-case of --vo=mediacodec_embed.
          // Not doing so causes error "Could not open codec." & video never gets rendered.
          if (configuration.vo == 'mediacodec_embed') 'vid': vidValue,
        },
      );
      // Kivo patch: upstream seeks to player.state.position here, every time.
      // Re-setting --vo already makes mpv re-create the video chain and
      // refresh the stream at the current position; while playing that seek
      // only flushed the audio and jumped back to a stale position. A paused
      // picture still needs one to be redrawn — to the exact frame on screen.
      if (widValue != '0' && !player.state.playing) {
        try {
          final at = (await platform.getProperty('time-pos')).trim();
          if (double.tryParse(at) != null) {
            await platform.command(['seek', at, 'absolute+exact']);
          } else {
            await player.seek(player.state.position);
          }
        } catch (_) {
          await player.seek(player.state.position);
        }
      }
      kivoTrace?.call('media_kit vo re-init done');
      if (widValue != '0') kivoSurfaceBusy.value = false;
    });
  }

  /// [StreamSubscription] for listening to video [Rect].
  StreamSubscription<VideoParams>? videoParamsSubscription;

  /// {@macro android_video_controller}
  AndroidVideoController._(
    super.player,
    super.configuration,
  ) {
    wid.addListener(widListener);
    videoParamsSubscription = player.stream.videoParams.listen((event) {
      final int width;
      final int height;
      if (event.rotate == 0 || event.rotate == 180) {
        width = event.dw ?? 0;
        height = event.dh ?? 0;
      } else {
        // width & height are swapped for 90 or 270 degrees rotation.
        width = event.dh ?? 0;
        height = event.dw ?? 0;
      }
      if (width == 0 || height == 0) {
        return;
      }
      // Kivo patch: [rect] is the video's own size, set right away — not
      // behind the lock — so the first frame is never laid out at the
      // previous video's shape.
      _kivoVideoRect =
          Rect.fromLTWH(0.0, 0.0, width.toDouble(), height.toDouble());
      if (rect.value != _kivoVideoRect) rect.value = _kivoVideoRect;
      lock.synchronized(() async {
        await _kivoEnsure(width, height);
        await _kivoBlendFor(width, height);
        if (!waitUntilFirstFrameRenderedCompleter.isCompleted) {
          waitUntilFirstFrameRenderedCompleter.complete();
        }
      });
    });
  }

  /// {@macro android_video_controller}
  static Future<PlatformVideoController> create(
    Player player,
    VideoControllerConfiguration configuration,
  ) async {
    Future<String> getDefaultHwdec() async {
      // Enforce software rendering in emulators.
      bool hw = configuration.enableHardwareAcceleration;
      final bool isEmulator = await _channel.invokeMethod('Utils.IsEmulator');
      if (isEmulator) {
        hw = false;
        debugPrint('media_kit: Emulator detected.');
        debugPrint('media_kit: Enforcing S/W rendering.');
      }
      return hw ? 'auto-safe' : 'no';
    }

    // Update [configuration] to have default values.
    configuration = configuration.copyWith(
      vo: configuration.vo ?? 'gpu',
      hwdec: configuration.hwdec ?? await getDefaultHwdec(),
    );

    // Retrieve the native handle of the [Player].
    final handle = await player.handle;
    // Return the existing [VideoController] if it's already created.
    if (_controllers.containsKey(handle)) {
      return _controllers[handle]!;
    }

    // In case no video-decoders are found, this means media_kit_libs_***_audio is being used.
    // Thus, --vid=no is required to prevent libmpv from trying to decode video (otherwise bad things may happen).
    //
    // Search for common H264 decoder to check if video support is available.
    final decoders = await queryDecoders(handle);
    if (!decoders.contains('h264')) {
      throw UnsupportedError(
        '[VideoController] is not available.'
        ' '
        'Please use media_kit_libs_***_video instead of media_kit_libs_***_audio.',
      );
    }

    // Creation:
    final controller = AndroidVideoController._(
      player,
      configuration,
    );

    // Register [_dispose] for execution upon [Player.dispose].
    player.platform?.release.add(controller._dispose);

    // Store the [VideoController] in the [_controllers].
    _controllers[handle] = controller;

    await _channel.invokeMethod(
      'VideoOutputManager.Create',
      {
        'handle': handle.toString(),
      },
    );

    await controller.setProperties(
      {
        // It is necessary to set vo=null here to avoid SIGSEGV, --wid must be assigned before vo=gpu is set.
        'vo': 'null',
        'hwdec': configuration.hwdec!,
        'vid': 'auto',
        'opengl-es': 'yes',
        'force-window': 'yes',
        'gpu-context': 'android',
        'sub-use-margins': 'no',
        'sub-font-provider': 'none',
        'sub-scale-with-window': 'yes',
        'hwdec-codecs': 'h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1',
        // Kivo patch: every video fills the (fixed) surface; Flutter restores
        // its aspect ratio from [rect] (subtitles: see _kivoBlendFor).
        'keepaspect': 'no',
      },
    );
    // Kivo patch: size the surface to the screen now, before any video.
    await controller._kivoPresize();

    // Return the [PlatformVideoController].
    return controller;
  }

  /// Sets the required size of the video output.
  /// This may yield substantial performance improvements if a small [width] & [height] is specified.
  ///
  /// Remember:
  /// * “Premature optimization is the root of all evil”
  /// * “With great power comes great responsibility”
  @override
  Future<void> setSize({
    int? width,
    int? height,
  }) {
    throw UnsupportedError(
      '[AndroidVideoController.setSize] is not available on Android',
    );
  }

  /// Disposes the instance. Releases allocated resources back to the system.
  Future<void> _dispose() async {
    super.dispose();
    wid.dispose();
    wid.removeListener(widListener);
    await videoParamsSubscription?.cancel();
    final handle = await player.handle;
    _controllers.remove(handle);
    await _channel.invokeMethod(
      'VideoOutputManager.Dispose',
      {
        'handle': handle.toString(),
      },
    );
  }

  /// Currently created [AndroidVideoController]s.
  static final _controllers = HashMap<int, AndroidVideoController>();

  /// [MethodChannel] for invoking platform specific native implementation.
  static final _channel =
      const MethodChannel('com.alexmercerind/media_kit_video')
        ..setMethodCallHandler(
          (MethodCall call) async {
            try {
              debugPrint(call.method.toString());
              debugPrint(call.arguments.toString());
              switch (call.method) {
                case 'VideoOutput.Resize':
                  {
                    // Notify about updated texture ID & [Rect].
                    final int handle = call.arguments['handle'];
                    final Rect rect = Rect.fromLTWH(
                      call.arguments['rect']['left'] * 1.0,
                      call.arguments['rect']['top'] * 1.0,
                      call.arguments['rect']['width'] * 1.0,
                      call.arguments['rect']['height'] * 1.0,
                    );
                    final int id = call.arguments['id'];
                    final int wid = call.arguments['wid'];
                    // Kivo patch: once a video's size is known, [rect] keeps it —
                    // the surface is bigger and stretched; Flutter must lay the
                    // texture out at the VIDEO's size to undo the stretch.
                    final c = _controllers[handle];
                    c?.rect.value = c._kivoVideoRect ?? rect;
                    if (wid != 0) c?._kivoNewSurface = true;
                    _controllers[handle]?.id.value = id;
                    _controllers[handle]?.wid.value = wid;
                    break;
                  }
                case 'VideoOutput.WaitUntilFirstFrameRenderedNotify':
                  {
                    // Notify about updated texture ID & [Rect].
                    final int handle = call.arguments['handle'];
                    debugPrint(handle.toString());
                    // Notify about the first frame being rendered.
                    final completer = _controllers[handle]
                        ?.waitUntilFirstFrameRenderedCompleter;
                    if (!(completer?.isCompleted ?? true)) {
                      completer?.complete();
                    }
                    break;
                  }
                default:
                  {
                    break;
                  }
              }
            } catch (exception, stacktrace) {
              debugPrint(exception.toString());
              debugPrint(stacktrace.toString());
            }
          },
        );
}

/// Kivo patch: a pair of pixel sizes (this package predates Dart records).
class _KivoSize {
  final int a;
  final int b;
  const _KivoSize(this.a, this.b);
}
