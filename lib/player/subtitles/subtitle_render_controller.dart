import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_provider.dart';
import '../../platform/subtitle_transcoder_provider.dart';
import '../engine/playback_provider.dart';
import 'subtitle_render.dart';

/// Who draws the current subtitle right now; Kivo's overlay reads it.
final subtitleDrawerProvider =
    StateProvider<SubtitleDrawer>((ref) => SubtitleDrawer.none);

/// Keeps mpv's `sub-visibility` in line with [drawerFor]: on only while mpv
/// is the one drawing (pictures, and ASS in its own style), off whenever
/// Kivo's overlay draws the text — otherwise both would, one on top of the
/// other.
///
/// App-scoped: tracks change while the player is minimized too.
class SubtitleRenderController {
  SubtitleRenderController(this._ref);

  final Ref _ref;
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _fontsReady = false;
  bool? _mpvDrawsWritten;
  Future<void> _chain = Future.value();
  Timer? _settle;

  void _listen() {
    final engine = _ref.read(playbackEngineProvider);
    _subs.add(engine.currentSubtitleTrackStream.listen((_) => _onTrackEvent()));
    _subs.add(engine.subtitleTracksStream.listen((_) => _onTrackEvent()));
  }

  /// Hands libass its font, then derives the first state. Called once at
  /// app start, before any video opens.
  Future<void> start() async {
    try {
      final font = await _ref.read(subtitleTranscoderProvider).systemSubtitleFont();
      if (font != null) {
        await _ref
            .read(playbackEngineProvider)
            .configureSubtitleFonts(dir: font.dir, family: font.family);
        _fontsReady = true;
      }
    } catch (e) {
      // No font: ASS is drawn by Kivo instead (see drawerFor).
      debugPrint('SubtitleRenderController font setup failed: $e');
    }
    await refresh();
  }

  void _onTrackEvent() {
    refresh();
    // mpv switches tracks asynchronously: the codec read right on the event
    // can still be the previous track's. One more look once it has settled.
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 400), refresh);
  }

  /// Re-reads the current track and applies the drawer.
  Future<void> refresh() {
    final next = _chain.then((_) => _refresh());
    _chain = next.catchError((Object _) {});
    return next;
  }

  Future<void> _refresh() async {
    final engine = _ref.read(playbackEngineProvider);
    final hasTrack = engine.currentSubtitleTrack != null;
    String? codec;
    if (hasTrack) {
      try {
        codec = await engine.currentSubtitleCodec();
      } catch (_) {
        codec = null;
      }
    }
    final drawer = drawerFor(
      hasTrack: hasTrack,
      codec: codec,
      respectAssStyle: _ref.read(settingsProvider).subtitleRespectAss,
      fontsReady: _fontsReady,
    );
    final mpvDraws = drawer == SubtitleDrawer.mpv;
    if (_mpvDrawsWritten != mpvDraws) {
      try {
        await engine.setSubtitleRendering(mpvDraws: mpvDraws);
        _mpvDrawsWritten = mpvDraws;
      } catch (e) {
        debugPrint('SubtitleRenderController write failed: $e');
      }
    }
    _ref.read(subtitleDrawerProvider.notifier).state = drawer;
  }

  void dispose() {
    _settle?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}

final subtitleRenderProvider = Provider<SubtitleRenderController>((ref) {
  final c = SubtitleRenderController(ref);
  ref.onDispose(c.dispose);
  c._listen();
  ref.listen(settingsProvider.select((s) => s.subtitleRespectAss),
      (_, __) => c.refresh());
  return c;
});
