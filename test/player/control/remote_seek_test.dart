import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/control/remote_seek.dart';

void main() {
  test(
    'tap uses configured step; holds accumulate before decoder reports position',
    () {
      fakeAsync((time) {
        final seeks = <(Duration, int)>[];
        final seek = RemoteSeek(
          position: () => const Duration(minutes: 1),
          duration: () => const Duration(minutes: 10),
          onSeek: (target, delta) => seeks.add((target, delta)),
        );
        seek.start(1, seconds: 3, progressive: true);
        expect(seeks.single, (const Duration(seconds: 63), 3));
        time.elapse(const Duration(milliseconds: 449));
        expect(seeks.length, 1);
        time.elapse(const Duration(milliseconds: 1));
        expect(seeks.last, (const Duration(seconds: 66), 3));
        time.elapse(const Duration(milliseconds: 200));
        expect(seeks.last, (const Duration(seconds: 69), 3));
        seek.stop();
        time.elapse(const Duration(seconds: 10));
        expect(seeks.length, 3);
      });
    },
  );

  test('hold speeds up after 2 and 4 seconds; release resets acceleration', () {
    fakeAsync((time) {
      final steps = <int>[];
      final seek = RemoteSeek(
        position: () => const Duration(minutes: 5),
        duration: () => const Duration(hours: 2),
        onSeek: (_, delta) => steps.add(delta),
      );
      seek.start(1, seconds: 3, progressive: true);
      time.elapse(const Duration(milliseconds: 2050));
      expect(steps.last, 9);
      time.elapse(const Duration(seconds: 2));
      expect(steps.last, 30);
      seek.stop();
      seek.start(-1, seconds: 3, progressive: true);
      expect(steps.last, -3);
      seek.stop();
    });
  });

  test('fixed seeking never accelerates and all seeks stay in the video', () {
    fakeAsync((time) {
      final targets = <Duration>[];
      final seek = RemoteSeek(
        position: () => const Duration(seconds: 95),
        duration: () => const Duration(seconds: 100),
        onSeek: (target, _) => targets.add(target),
      );
      seek.start(1, seconds: 3, progressive: false);
      time.elapse(const Duration(seconds: 6));
      expect(targets, [
        const Duration(seconds: 98),
        const Duration(seconds: 100),
      ]);
      seek.stop();
      seek.start(-1, seconds: 60, progressive: true);
      time.elapse(const Duration(seconds: 1));
      expect(targets.last, Duration.zero);
      seek.stop();
    });
  });

  test('unknown duration does not seek or restart the video', () {
    fakeAsync((time) {
      var commands = 0;
      final seek = RemoteSeek(
        position: () => Duration.zero,
        duration: () => Duration.zero,
        onSeek: (_, __) => commands++,
      );
      seek.start(1, seconds: 3, progressive: true);
      time.elapse(const Duration(seconds: 8));
      expect(commands, 0);
      seek.stop();
    });
  });
}
