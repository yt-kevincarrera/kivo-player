import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/manual_subtitle_controller.dart';
import 'package:kivo_player/player/tracks/subtitle_importer.dart';
import 'package:kivo_player/player/tracks/subtitle_prefs_store.dart';
import '../../fakes/fakes.dart'; // FakeSubtitleImporter lives here, added in Task 9

ProviderContainer _c(FakePlaybackEngine engine, FakeSubtitleImporter importer,
        SubtitlePrefsStore store) =>
    ProviderContainer(overrides: [
      playbackEngineProvider.overrideWithValue(engine),
      subtitleImporterProvider.overrideWithValue(importer),
      subtitlePrefsStoreProvider.overrideWithValue(store),
    ]);

void main() {
  test('a picked subtitle is copied, applied and remembered', () async {
    final engine = FakePlaybackEngine();
    final store = InMemorySubtitlePrefsStore();
    final c = _c(engine, FakeSubtitleImporter(), store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0));

    expect(await c.read(manualSubtitleProvider).load('/picked/foo.srt'), true);

    expect(engine.externalSubtitles.single, '/app/subs/ep1.mkv.srt');
    expect(store.forKey('ep1.mkv')!.subtitlePath, '/app/subs/ep1.mkv.srt');
  });

  test('a failed copy applies nothing and remembers nothing', () async {
    final engine = FakePlaybackEngine();
    final store = InMemorySubtitlePrefsStore();
    final c = _c(engine, FakeSubtitleImporter()..result = null, store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0));

    expect(await c.read(manualSubtitleProvider).load('/picked/foo.srt'), false);
    expect(engine.externalSubtitles, isEmpty);
    expect(store.forKey('ep1.mkv'), isNull);
  });

  test('an existing delay survives loading a new subtitle', () async {
    final store = InMemorySubtitlePrefsStore();
    await store.put('ep1.mkv', const VideoSubtitlePrefs(delayMs: 400));
    final c = _c(FakePlaybackEngine(), FakeSubtitleImporter(), store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0));

    await c.read(manualSubtitleProvider).load('/picked/foo.srt');
    expect(store.forKey('ep1.mkv')!.delayMs, 400);
  });

  test('loading with no video open is refused', () async {
    final c = _c(FakePlaybackEngine(), FakeSubtitleImporter(), InMemorySubtitlePrefsStore());
    addTearDown(c.dispose);
    expect(await c.read(manualSubtitleProvider).load('/picked/foo.srt'), false);
  });
}
