import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/error_log_provider.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/platform/image_saver_provider.dart';
import 'package:kivo_player/platform/interfaces/image_saver.dart';
import 'package:kivo_player/player/capture/frame_capture_controller.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import '../../fakes/fakes.dart';

class FakeImageSaver implements ImageSaver {
  /// What [save] hands back; null simulates a gallery write that failed.
  String? result = 'content://media/1';
  final List<(Uint8List, String)> saved = [];
  final List<String> viewed = [];

  @override
  Future<String?> save(Uint8List bytes, String fileName) async {
    saved.add((bytes, fileName));
    return result;
  }

  @override
  Future<void> view(String uri) async => viewed.add(uri);
}

VideoSession _session() => const VideoSession(
      playbackPath: '/v/ep1.mkv',
      displayName: 'ep1.mkv',
      queue: ['/v/ep1.mkv'],
      index: 0,
    );

Future<ProviderContainer> _c({
  required FakeFrameExtractor extractor,
  required FakeImageSaver saver,
  FakePlaybackEngine? engine,
  ErrorLog? log,
}) async {
  return ProviderContainer(overrides: [
    playbackEngineProvider.overrideWithValue(engine ?? FakePlaybackEngine()),
    frameExtractorProvider.overrideWithValue(extractor),
    imageSaverProvider.overrideWithValue(saver),
    if (log != null) errorLogProvider.overrideWithValue(log),
  ]);
}

void main() {
  testWidgets('captures the current frame and hands back what it saved',
      (tester) async {
    final engine = FakePlaybackEngine();
    final extractor = FakeFrameExtractor()..bytes = Uint8List.fromList([1, 2, 3]);
    final saver = FakeImageSaver();
    final c = await _c(extractor: extractor, saver: saver, engine: engine);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session());
    // Drive the position stream the player already exposes.
    c.listen(positionProvider, (_, __) {});
    engine.emitPosition(const Duration(minutes: 12, seconds: 34));
    await tester.pump();

    final result = await c.read(frameCaptureProvider).capture();

    expect(result.uri, 'content://media/1');
    expect(result.bytes, [1, 2, 3]);
    expect(saver.saved.single.$2, 'ep1 — 12m34s.jpg');
    // The extractor is prepared for the open video before asking for a frame;
    // prepare() is idempotent so doing it again costs nothing.
    expect(extractor.prepared.last, '/v/ep1.mkv');
  });

  test('refuses when no video is open', () async {
    final extractor = FakeFrameExtractor()..bytes = Uint8List.fromList([1]);
    final saver = FakeImageSaver();
    final c = await _c(extractor: extractor, saver: saver);
    addTearDown(c.dispose);

    final result = await c.read(frameCaptureProvider).capture();

    expect(result.ok, false);
    expect(saver.saved, isEmpty);
  });

  test('a frame that cannot be decoded reports KV-503 and saves nothing',
      () async {
    final log = ErrorLog(InMemoryErrorLogStore(), appVersion: '1', androidSdk: 1);
    final extractor = FakeFrameExtractor()..returnsNull = true;
    final saver = FakeImageSaver();
    final c = await _c(extractor: extractor, saver: saver, log: log);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session());

    final result = await c.read(frameCaptureProvider).capture();

    expect(result.ok, false);
    expect(saver.saved, isEmpty);
    expect(log.entries().single.code, 'KV-503');
  });

  test('a gallery write that fails reports KV-503', () async {
    final log = ErrorLog(InMemoryErrorLogStore(), appVersion: '1', androidSdk: 1);
    final extractor = FakeFrameExtractor()..bytes = Uint8List.fromList([1]);
    final saver = FakeImageSaver()..result = null;
    final c = await _c(extractor: extractor, saver: saver, log: log);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session());

    final result = await c.read(frameCaptureProvider).capture();

    expect(result.ok, false);
    expect(log.entries().single.code, 'KV-503');
  });

  test('an extractor that throws is caught, not propagated', () async {
    final log = ErrorLog(InMemoryErrorLogStore(), appVersion: '1', androidSdk: 1);
    final extractor = FakeFrameExtractor()..throwOnFrame = true;
    final c = await _c(extractor: extractor, saver: FakeImageSaver(), log: log);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session());

    // A capture is a side feature; it must never take playback down with it.
    final result = await c.read(frameCaptureProvider).capture();

    expect(result.ok, false);
    expect(log.entries().single.code, 'KV-503');
  });
}
