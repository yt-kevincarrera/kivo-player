import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/subtitle_prefs_store.dart';
import 'package:kivo_player/player/tracks/subtitle_sync_controller.dart';
import '../../fakes/fakes.dart';

VideoSession _session(String name) =>
    VideoSession(playbackPath: '/v/$name', displayName: name, queue: ['/v/$name'], index: 0);

ProviderContainer _c(FakePlaybackEngine engine, SubtitlePrefsStore store) =>
    ProviderContainer(overrides: [
      playbackEngineProvider.overrideWithValue(engine),
      subtitlePrefsStoreProvider.overrideWithValue(store),
    ]);

void main() {
  test('a burst of nudges reaches mpv exactly once, with the last value', () {
    fakeAsync((async) {
      final engine = FakePlaybackEngine();
      final c = _c(engine, InMemorySubtitlePrefsStore());
      addTearDown(c.dispose);
      c.read(currentVideoProvider.notifier).open(_session('ep1.mkv'));

      final sync = c.read(subtitleSyncProvider.notifier);
      for (var i = 0; i < 12; i++) {
        sync.nudge(1);
      }
      // The UI already shows the final value before mpv has heard anything.
      expect(c.read(subtitleSyncProvider), 600);
      expect(engine.subtitleDelays, isEmpty);

      async.elapse(const Duration(milliseconds: 200));
      expect(engine.subtitleDelays, [0.6]);
    });
  });

  test('the settled offset is persisted for that video', () {
    fakeAsync((async) {
      final store = InMemorySubtitlePrefsStore();
      final c = _c(FakePlaybackEngine(), store);
      addTearDown(c.dispose);
      c.read(currentVideoProvider.notifier).open(_session('ep1.mkv'));

      c.read(subtitleSyncProvider.notifier).nudge(4);
      async.elapse(const Duration(milliseconds: 200));
      expect(store.forKey('ep1.mkv')!.delayMs, 200);
    });
  });

  test('opening a video restores its stored offset', () async {
    final store = InMemorySubtitlePrefsStore();
    await store.put('ep2.mkv', const VideoSubtitlePrefs(delayMs: -750));
    final c = _c(FakePlaybackEngine(), store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('ep2.mkv'));
    expect(c.read(subtitleSyncProvider), -750);
  });

  test('reset returns to zero and clears the stored offset', () {
    fakeAsync((async) {
      final store = InMemorySubtitlePrefsStore();
      final c = _c(FakePlaybackEngine(), store);
      addTearDown(c.dispose);
      c.read(currentVideoProvider.notifier).open(_session('ep1.mkv'));

      c.read(subtitleSyncProvider.notifier).nudge(4);
      async.elapse(const Duration(milliseconds: 200));
      c.read(subtitleSyncProvider.notifier).reset();
      async.elapse(const Duration(milliseconds: 200));

      expect(c.read(subtitleSyncProvider), 0);
      expect(store.forKey('ep1.mkv'), isNull);
    });
  });

  test('flush applies a pending nudge immediately instead of losing it', () async {
    final engine = FakePlaybackEngine();
    final c = _c(engine, InMemorySubtitlePrefsStore());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('ep1.mkv'));

    c.read(subtitleSyncProvider.notifier).nudge(2);
    await c.read(subtitleSyncProvider.notifier).flush();
    expect(engine.subtitleDelays, [0.1]);
  });

  test('nudging with no video open does nothing', () {
    final engine = FakePlaybackEngine();
    final c = _c(engine, InMemorySubtitlePrefsStore());
    addTearDown(c.dispose);
    c.read(subtitleSyncProvider.notifier).nudge(1);
    expect(c.read(subtitleSyncProvider), 0);
    expect(engine.subtitleDelays, isEmpty);
  });
}
