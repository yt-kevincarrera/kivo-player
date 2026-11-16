import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/engine/video_progress.dart';
import 'package:kivo_player/player/decoder/video_progress_watchdog.dart';

VideoProgress sample(
  int at, {
  int? picture,
  int? audio,
  bool paused = false,
  bool seeking = false,
}) => VideoProgress(
  sampledAt: Duration(seconds: at),
  position: Duration(seconds: audio ?? at),
  videoPosition: Duration(milliseconds: picture ?? at * 1000),
  paused: paused,
  seeking: seeking,
);
const timeout = Duration(seconds: 3);
void main() {
  test('only frozen video with an advancing audio clock triggers once', () {
    final guard = VideoProgressWatchdog();
    expect(
      guard.update(sample(0, picture: 1000), timeout: timeout, enabled: true),
      false,
    );
    expect(
      guard.update(sample(2, picture: 1000), timeout: timeout, enabled: true),
      false,
    );
    expect(
      guard.update(sample(3, picture: 1000), timeout: timeout, enabled: true),
      true,
    );
    expect(
      guard.update(sample(6, picture: 1000), timeout: timeout, enabled: true),
      false,
    );
  });
  test('slow but advancing video is not a freeze', () {
    final guard = VideoProgressWatchdog();
    for (var i = 0; i < 20; i++) {
      expect(
        guard.update(
          sample(i, picture: (i ~/ 2) * 100),
          timeout: timeout,
          enabled: true,
        ),
        false,
      );
    }
  });
  test(
    'both clocks stopped is not mistaken for hardware failing behind audio',
    () {
      final guard = VideoProgressWatchdog();
      for (var i = 0; i < 20; i++) {
        expect(
          guard.update(
            sample(i, picture: 0, audio: 0),
            timeout: timeout,
            enabled: true,
          ),
          false,
        );
      }
    },
  );
  for (final mode in ['paused', 'seeking', 'disabled', 'missing video clock']) {
    test('$mode resets elapsed failure time', () {
      final guard = VideoProgressWatchdog();
      guard.update(sample(0, picture: 0), timeout: timeout, enabled: true);
      guard.update(sample(2, picture: 0), timeout: timeout, enabled: true);
      final interruption = mode == 'missing video clock'
          ? const VideoProgress(
              position: Duration(seconds: 8),
              videoPosition: null,
              sampledAt: Duration(seconds: 8),
            )
          : sample(
              8,
              picture: 0,
              paused: mode == 'paused',
              seeking: mode == 'seeking',
            );
      expect(
        guard.update(
          interruption,
          timeout: timeout,
          enabled: mode != 'disabled',
        ),
        false,
      );
      expect(
        guard.update(sample(9, picture: 0), timeout: timeout, enabled: true),
        false,
      );
      expect(
        guard.update(sample(11, picture: 0), timeout: timeout, enabled: true),
        false,
      );
      expect(
        guard.update(sample(12, picture: 0), timeout: timeout, enabled: true),
        true,
      );
    });
  }
}
