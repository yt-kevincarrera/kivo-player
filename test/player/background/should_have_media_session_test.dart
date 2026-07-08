import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/background/background_playback.dart';

void main() {
  test('shouldHaveMediaSession: only when backgrounded, has a video, and not in PiP', () {
    expect(shouldHaveMediaSession(inBackground: true, hasVideo: true, inPip: false), true);
    // paused-in-background with a loaded video → still true (the bug-2 case)
    expect(shouldHaveMediaSession(inBackground: true, hasVideo: true, inPip: false), true);
    // foreground → no session
    expect(shouldHaveMediaSession(inBackground: false, hasVideo: true, inPip: false), false);
    // no video loaded → no session
    expect(shouldHaveMediaSession(inBackground: true, hasVideo: false, inPip: false), false);
    // PiP owns the controls → no session
    expect(shouldHaveMediaSession(inBackground: true, hasVideo: true, inPip: true), false);
  });
}
