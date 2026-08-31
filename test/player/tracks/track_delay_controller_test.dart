import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import 'package:kivo_player/player/tracks/track_delay_controller.dart';
import '../../fakes/fakes.dart';

VideoSession _session(String name) =>
    VideoSession(playbackPath: '/v/$name', displayName: name, queue: ['/v/$name'], index: 0);

ProviderContainer _c(FakePlaybackEngine engine, TrackPrefsStore store) =>
    ProviderContainer(overrides: [
      playbackEngineProvider.overrideWithValue(engine),
      trackPrefsStoreProvider.overrideWithValue(store),
    ]);

void main() {
  test('a burst of nudges reaches mpv exactly once, with the last value', () {
    fakeAsync((async) {
      final engine = FakePlaybackEngine();
      final c = _c(engine, InMemoryTrackPrefsStore());
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
      final store = InMemoryTrackPrefsStore();
      final c = _c(FakePlaybackEngine(), store);
      addTearDown(c.dispose);
      c.read(currentVideoProvider.notifier).open(_session('ep1.mkv'));

      c.read(subtitleSyncProvider.notifier).nudge(4);
      async.elapse(const Duration(milliseconds: 200));
      expect(store.forKey('ep1.mkv')!.subtitleDelayMs, 200);
    });
  });

  test('opening a video restores its stored offset', () async {
    final store = InMemoryTrackPrefsStore();
    await store.put('ep2.mkv', const VideoTrackPrefs(subtitleDelayMs: -750));
    final c = _c(FakePlaybackEngine(), store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('ep2.mkv'));
    expect(c.read(subtitleSyncProvider), -750);
  });

  test('reset returns to zero and clears the stored offset', () {
    fakeAsync((async) {
      final store = InMemoryTrackPrefsStore();
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
    final c = _c(engine, InMemoryTrackPrefsStore());
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('ep1.mkv'));

    c.read(subtitleSyncProvider.notifier).nudge(2);
    await c.read(subtitleSyncProvider.notifier).flush();
    expect(engine.subtitleDelays, [0.1]);
  });

  // ref.onDispose cancels the pending timer when the notifier is rebuilt for
  // the new video. Without it the debounce would land after the switch and
  // write video A's offset onto video B — both in mpv and in B's prefs.
  test('switching video mid-debounce drops the pending nudge', () {
    fakeAsync((async) {
      final engine = FakePlaybackEngine();
      final store = InMemoryTrackPrefsStore();
      store.put('ep2.mkv', const VideoTrackPrefs(subtitleDelayMs: -300));
      final c = _c(engine, store);
      addTearDown(c.dispose);
      // The HUD watches this provider, so keep a listener: the rebuild has to
      // happen the way it does on screen, not only on the next read.
      c.listen(subtitleSyncProvider, (_, __) {});
      c.read(currentVideoProvider.notifier).open(_session('ep1.mkv'));

      c.read(subtitleSyncProvider.notifier).nudge(4);
      c.read(currentVideoProvider.notifier).open(_session('ep2.mkv'));
      expect(c.read(subtitleSyncProvider), -300); // rebuilt for the new video

      async.elapse(const Duration(milliseconds: 200));
      expect(engine.subtitleDelays, isEmpty);
      expect(store.forKey('ep1.mkv'), isNull);
      expect(store.forKey('ep2.mkv')!.subtitleDelayMs, -300);
    });
  });

  test('nudging with no video open does nothing', () {
    final engine = FakePlaybackEngine();
    final c = _c(engine, InMemoryTrackPrefsStore());
    addTearDown(c.dispose);
    c.read(subtitleSyncProvider.notifier).nudge(1);
    expect(c.read(subtitleSyncProvider), 0);
    expect(engine.subtitleDelays, isEmpty);
  });
  test('an audio burst reaches mpv once, on the audio channel only', () {
    fakeAsync((async) {
      final engine = FakePlaybackEngine();
      final c = _c(engine, InMemoryTrackPrefsStore());
      addTearDown(c.dispose);
      c.read(currentVideoProvider.notifier).open(_session('ep1.mkv'));

      final audio = c.read(audioSyncProvider.notifier);
      for (var i = 0; i < 8; i++) {
        audio.nudge(-1);
      }
      expect(c.read(audioSyncProvider), -400);
      expect(engine.audioDelays, isEmpty);

      async.elapse(const Duration(milliseconds: 200));
      expect(engine.audioDelays, [-0.4]);
      // The subtitle channel was never touched.
      expect(engine.subtitleDelays, isEmpty);
    });
  });

  test('the two offsets are stored side by side, neither clobbering the other',
      () {
    fakeAsync((async) {
      final store = InMemoryTrackPrefsStore();
      final c = _c(FakePlaybackEngine(), store);
      addTearDown(c.dispose);
      c.read(currentVideoProvider.notifier).open(_session('ep1.mkv'));

      c.read(subtitleSyncProvider.notifier).nudge(4); // +200 ms
      async.elapse(const Duration(milliseconds: 200));
      c.read(audioSyncProvider.notifier).nudge(-2); // -100 ms
      async.elapse(const Duration(milliseconds: 200));

      expect(store.forKey('ep1.mkv')!.subtitleDelayMs, 200);
      expect(store.forKey('ep1.mkv')!.audioDelayMs, -100);
    });
  });

  test('opening a video restores its stored audio offset', () async {
    final store = InMemoryTrackPrefsStore();
    await store.put('ep2.mkv', const VideoTrackPrefs(audioDelayMs: 350));
    final c = _c(FakePlaybackEngine(), store);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('ep2.mkv'));
    expect(c.read(audioSyncProvider), 350);
    expect(c.read(subtitleSyncProvider), 0);
  });

}
