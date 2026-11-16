// Headless host check of the real libmpv client/probe, not device acceptance.
// dart run scripts/native/video_progress_probe.dart <libmpv> <static-video>
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as mpv;
import 'package:kivo_player/player/engine/native_video_probe.dart';
import 'package:kivo_player/player/engine/video_progress.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('Expected library and fixture paths');
  }
  final api = mpv.MPV(DynamicLibrary.open(args[0]));
  final player = api.mpv_create();
  if (player == nullptr) throw StateError('mpv_create failed');
  void option(String key, String value) {
    final k = key.toNativeUtf8();
    final v = value.toNativeUtf8();
    final result = api.mpv_set_option_string(player, k.cast(), v.cast());
    calloc.free(k);
    calloc.free(v);
    if (result < 0) throw StateError('Option $key failed: $result');
  }

  final probe = NativeVideoProbe(library: args[0], handle: player.address);
  StreamSubscription<VideoProgress>? subscription;
  try {
    option('vo', 'null');
    option('ao', 'null');
    option('hwdec', 'no');
    option('terminal', 'no');
    option('config', 'no');
    option('idle', 'yes');
    if (api.mpv_initialize(player) < 0) {
      throw StateError('mpv_initialize failed');
    }
    await probe.start();
    probe.beginSession();
    final samples = <VideoProgress>[];
    subscription = probe.stream.listen(samples.add);
    final parts = ['loadfile', args[1]].map((s) => s.toNativeUtf8()).toList();
    final command = calloc<Pointer<Int8>>(parts.length + 1);
    for (var i = 0; i < parts.length; i++) {
      command[i] = parts[i].cast();
    }
    final status = api.mpv_command(player, command);
    for (final part in parts) {
      calloc.free(part);
    }
    calloc.free(command);
    if (status < 0) throw StateError('loadfile failed: $status');
    await Future<void>.delayed(const Duration(seconds: 3));
    final frames = samples.where((s) => s.videoPosition != null).toList();
    if (frames.length < 3 ||
        frames.last.videoPosition! - frames.first.videoPosition! <
            const Duration(seconds: 1)) {
      throw StateError(
        'Video timestamps did not progress: ${samples.map((s) => s.videoPosition)}',
      );
    }
    if (samples.last.position == null) {
      throw StateError('Playback clock missing');
    }
    stdout.writeln(
      'PASS static image still has advancing video timestamps: '
      '${frames.first.videoPosition!.inMilliseconds} -> '
      '${frames.last.videoPosition!.inMilliseconds} ms; ${samples.length} samples',
    );
    await probe.dispose();
    stdout.writeln('PASS observer detached without stopping the player');
  } finally {
    await subscription?.cancel();
    await probe.dispose();
    api.mpv_terminate_destroy(player);
  }
}
