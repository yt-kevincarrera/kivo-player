import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import '../../fakes/fakes.dart';

void main() {
  test('FakePlaybackEngine exposes configurable current-track snapshots', () {
    final e = FakePlaybackEngine();
    addTearDown(e.dispose);
    expect(e.currentSubtitleTracks, isEmpty);
    expect(e.currentSubtitleTrack, isNull);

    const spa = MediaTrack(id: 's', title: 'Español', language: 'spa');
    e.subtitleTracksValue = [spa];
    e.currentSubtitleTrackValue = spa;
    expect(e.currentSubtitleTracks, [spa]);
    expect(e.currentSubtitleTrack, spa);
  });
}
