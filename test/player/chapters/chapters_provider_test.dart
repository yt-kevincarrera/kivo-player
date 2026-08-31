import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/player/chapters/chapter.dart';
import 'package:kivo_player/player/chapters/chapters_provider.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/state/video_ready_state.dart';
import '../../fakes/fakes.dart';

const _chapters = [
  MediaChapter(title: 'Intro', start: Duration.zero),
  MediaChapter(title: 'Acto 1', start: Duration(minutes: 2)),
];

VideoSession _session(String name) => VideoSession(
      playbackPath: '/v/$name',
      displayName: name,
      queue: ['/v/$name'],
      index: 0,
    );

ProviderContainer _c(FakePlaybackEngine engine) => ProviderContainer(
      overrides: [playbackEngineProvider.overrideWithValue(engine)],
    );

void main() {
  test('nothing is read until the first frame lands', () async {
    final engine = FakePlaybackEngine()..chaptersValue = _chapters;
    final c = _c(engine);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('a.mkv'));

    expect(c.read(chaptersProvider), isEmpty);
    // This is the whole point: opening a video must not pay for chapters.
    expect(engine.chapterReads, 0);
  });

  test('the first frame triggers the read', () async {
    final engine = FakePlaybackEngine()..chaptersValue = _chapters;
    final c = _c(engine);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('a.mkv'));
    c.listen(chaptersProvider, (_, __) {});

    c.read(videoFrameReadyProvider.notifier).state = true;
    await Future<void>.delayed(Duration.zero);

    expect(c.read(chaptersProvider), _chapters);
    expect(engine.chapterReads, 1);
  });

  test('a file with no chapters simply reports none', () async {
    final engine = FakePlaybackEngine(); // chaptersValue defaults to empty
    final c = _c(engine);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('a.mkv'));
    c.listen(chaptersProvider, (_, __) {});
    c.read(videoFrameReadyProvider.notifier).state = true;
    await Future<void>.delayed(Duration.zero);

    expect(c.read(chaptersProvider), isEmpty);
  });

  test('switching video clears the chapters of the previous one', () async {
    final engine = FakePlaybackEngine()..chaptersValue = _chapters;
    final c = _c(engine);
    addTearDown(c.dispose);
    final videos = c.read(currentVideoProvider.notifier);
    videos.open(_session('a.mkv'));
    c.listen(chaptersProvider, (_, __) {});
    c.read(videoFrameReadyProvider.notifier).state = true;
    await Future<void>.delayed(Duration.zero);
    expect(c.read(chaptersProvider), isNotEmpty);

    videos.open(_session('b.mkv'));
    // Empty again immediately — the next video's chapters are unknown until
    // its own first frame, and showing the previous one's would be a lie.
    expect(c.read(chaptersProvider), isEmpty);
  });

  test('the current chapter follows the playhead', () async {
    final engine = FakePlaybackEngine()..chaptersValue = _chapters;
    final c = _c(engine);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session('a.mkv'));
    c.listen(chaptersProvider, (_, __) {});
    c.listen(positionProvider, (_, __) {});
    c.read(videoFrameReadyProvider.notifier).state = true;
    await Future<void>.delayed(Duration.zero);

    engine.emitPosition(const Duration(minutes: 5));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(currentChapterProvider)?.title, 'Acto 1');
  });
}
