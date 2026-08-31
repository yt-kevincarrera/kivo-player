import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/manual_subtitle_controller.dart';
import 'package:kivo_player/player/tracks/subtitle_importer.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import '../../fakes/fakes.dart'; // FakeSubtitleImporter lives here, added in Task 9

Future<ProviderContainer> _c(FakePlaybackEngine engine,
    FakeSubtitleImporter importer, TrackPrefsStore store) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    playbackEngineProvider.overrideWithValue(engine),
    subtitleImporterProvider.overrideWithValue(importer),
    trackPrefsStoreProvider.overrideWithValue(store),
  ]);
}

void main() {
  test('a picked subtitle is copied, applied and remembered', () async {
    final engine = FakePlaybackEngine();
    final store = InMemoryTrackPrefsStore();
    final c = await _c(engine, FakeSubtitleImporter(), store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0));

    expect(await c.read(manualSubtitleProvider).load('/picked/foo.srt'), true);

    // The title is the picked file's name, not the app-owned copy's videoKey
    // name — that is what the track picker lists.
    expect(engine.externalSubtitles.single, ('/app/subs/ep1.mkv.srt', 'foo.srt'));
    expect(store.forKey('ep1.mkv')!.subtitlePath, '/app/subs/ep1.mkv.srt');
  });

  // Otherwise the file plays while the "Mostrar subtítulos" switch reads off,
  // and the next open turns subtitles off before re-adding this file.
  test('loading a subtitle by hand turns subtitles on', () async {
    final c = await _c(
        FakePlaybackEngine(), FakeSubtitleImporter(), InMemoryTrackPrefsStore());
    addTearDown(c.dispose);
    await c.read(settingsProvider.notifier).set(
        c.read(settingsProvider).copyWith(subtitlesEnabledByDefault: false));
    c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0));

    await c.read(manualSubtitleProvider).load('/picked/foo.srt');
    expect(c.read(settingsProvider).subtitlesEnabledByDefault, true);
  });

  test('a failed copy applies nothing and remembers nothing', () async {
    final engine = FakePlaybackEngine();
    final store = InMemoryTrackPrefsStore();
    final c = await _c(engine, FakeSubtitleImporter()..result = null, store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0));

    expect(await c.read(manualSubtitleProvider).load('/picked/foo.srt'), false);
    expect(engine.externalSubtitles, isEmpty);
    expect(store.forKey('ep1.mkv'), isNull);
  });

  test('an existing delay survives loading a new subtitle', () async {
    final store = InMemoryTrackPrefsStore();
    await store.put('ep1.mkv', const VideoTrackPrefs(subtitleDelayMs: 400));
    final c = await _c(FakePlaybackEngine(), FakeSubtitleImporter(), store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/ep1.mkv', displayName: 'ep1.mkv', queue: ['/v/ep1.mkv'], index: 0));

    await c.read(manualSubtitleProvider).load('/picked/foo.srt');
    expect(store.forKey('ep1.mkv')!.subtitleDelayMs, 400);
  });

  test('loading with no video open is refused', () async {
    final c = await _c(
        FakePlaybackEngine(), FakeSubtitleImporter(), InMemoryTrackPrefsStore());
    addTearDown(c.dispose);
    expect(await c.read(manualSubtitleProvider).load('/picked/foo.srt'), false);
  });
}
