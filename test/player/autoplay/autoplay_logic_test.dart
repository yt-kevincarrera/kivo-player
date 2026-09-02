import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/autoplay/autoplay_logic.dart';

void main() {
  test('shouldAutoplay is true only when enabled, has next, no loop, no sleep-stop', () {
    expect(shouldAutoplay(enabled: true, hasNext: true, loopActive: false, sleepStopsHere: false), true);
    expect(shouldAutoplay(enabled: false, hasNext: true, loopActive: false, sleepStopsHere: false), false);
    expect(shouldAutoplay(enabled: true, hasNext: false, loopActive: false, sleepStopsHere: false), false);
    expect(shouldAutoplay(enabled: true, hasNext: true, loopActive: true, sleepStopsHere: false), false);
    expect(shouldAutoplay(enabled: true, hasNext: true, loopActive: false, sleepStopsHere: true), false);
  });

  test('repeat-list keeps hasNext true forever, but sleepStopsHere still wins', () {
    // Under repeat-list, peekNext() never returns null (it wraps to the
    // start), so hasNext is always true — that must not let the sleep
    // timer's "stop here" be overridden. Same for an active A-B loop.
    expect(shouldAutoplay(enabled: true, hasNext: true, loopActive: false, sleepStopsHere: true), false);
    expect(shouldAutoplay(enabled: true, hasNext: true, loopActive: true, sleepStopsHere: false), false);
  });
}
