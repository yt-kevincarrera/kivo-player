import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/queue/queue_order.dart';

void main() {
  group('repeatModeFor', () {
    test('parses each name back to its enum value', () {
      expect(repeatModeFor('off'), RepeatMode.off);
      expect(repeatModeFor('list'), RepeatMode.list);
      expect(repeatModeFor('video'), RepeatMode.video);
    });

    test('falls back to off for anything unrecognized', () {
      expect(repeatModeFor('bogus'), RepeatMode.off);
      expect(repeatModeFor(''), RepeatMode.off);
    });
  });

  group('shuffledOrder', () {
    test('is a permutation of 0..length-1 with current first', () {
      final order = shuffledOrder(6, 2, Random(1));
      expect(order.first, 2);
      expect(order.toSet(), {0, 1, 2, 3, 4, 5});
      expect(order.length, 6);
    });

    test('is stable across calls given the same seed', () {
      final a = shuffledOrder(8, 3, Random(42));
      final b = shuffledOrder(8, 3, Random(42));
      expect(a, b);
    });

    test('a one-item queue is just [current], same as shuffle off', () {
      expect(shuffledOrder(1, 0, Random(7)), [0]);
    });
  });

  group('nextIndex', () {
    test('off: walks forward, null past the end', () {
      const order = [0, 1, 2];
      expect(nextIndex(order: order, position: 0, mode: RepeatMode.off), 1);
      expect(nextIndex(order: order, position: 1, mode: RepeatMode.off), 2);
      expect(nextIndex(order: order, position: 2, mode: RepeatMode.off), null);
    });

    test('list: wraps to the first past the end', () {
      const order = [2, 0, 1]; // a shuffled order, current at position 0
      expect(nextIndex(order: order, position: 0, mode: RepeatMode.list), 0);
      expect(nextIndex(order: order, position: 2, mode: RepeatMode.list), 2);
    });

    test('video: always returns the same (current) index', () {
      const order = [2, 0, 1];
      expect(nextIndex(order: order, position: 0, mode: RepeatMode.video), 2);
      expect(nextIndex(order: order, position: 1, mode: RepeatMode.video), 0);
    });

    test('a one-item queue with shuffle on behaves exactly like shuffle off', () {
      final shuffledOn = shuffledOrder(1, 0, Random(99));
      const naturalOff = [0];
      expect(
        nextIndex(order: shuffledOn, position: 0, mode: RepeatMode.off),
        nextIndex(order: naturalOff, position: 0, mode: RepeatMode.off),
      );
      expect(
        nextIndex(order: shuffledOn, position: 0, mode: RepeatMode.list),
        nextIndex(order: naturalOff, position: 0, mode: RepeatMode.list),
      );
    });
  });

  group('previousIndex', () {
    test('off: walks backward, null before the start', () {
      const order = [0, 1, 2];
      expect(previousIndex(order: order, position: 2, mode: RepeatMode.off), 1);
      expect(previousIndex(order: order, position: 1, mode: RepeatMode.off), 0);
      expect(previousIndex(order: order, position: 0, mode: RepeatMode.off), null);
    });

    test('list: wraps to the last before the start', () {
      const order = [2, 0, 1];
      expect(previousIndex(order: order, position: 0, mode: RepeatMode.list), 1);
      expect(previousIndex(order: order, position: 2, mode: RepeatMode.list), 0);
    });

    test('video: always returns the same (current) index', () {
      const order = [2, 0, 1];
      expect(previousIndex(order: order, position: 0, mode: RepeatMode.video), 2);
      expect(previousIndex(order: order, position: 2, mode: RepeatMode.video), 1);
    });

    test('a one-item queue with shuffle on behaves exactly like shuffle off', () {
      final shuffledOn = shuffledOrder(1, 0, Random(5));
      const naturalOff = [0];
      expect(
        previousIndex(order: shuffledOn, position: 0, mode: RepeatMode.off),
        previousIndex(order: naturalOff, position: 0, mode: RepeatMode.off),
      );
    });
  });

  group('moveInOrder', () {
    test('moves forward and back', () {
      expect(moveInOrder([0, 1, 2, 3], 0, 2), [1, 2, 0, 3]);
      expect(moveInOrder([0, 1, 2, 3], 3, 1), [0, 3, 1, 2]);
    });

    test('same position is a copy', () {
      final o = [2, 0, 1];
      final m = moveInOrder(o, 1, 1);
      expect(m, o);
      expect(identical(m, o), isFalse);
    });
  });

  group('playNextInOrder', () {
    test('puts the item right after the current one', () {
      expect(playNextInOrder([0, 1, 2, 3, 4], 1, 4), [0, 1, 4, 2, 3]);
      expect(playNextInOrder([0, 1, 2, 3, 4], 3, 0), [1, 2, 3, 0, 4]);
    });

    test('re-inserts an item that had been removed', () {
      expect(playNextInOrder([0, 2], 0, 1), [0, 1, 2]);
    });

    test('the current video itself is a no-op', () {
      expect(playNextInOrder([0, 1, 2], 1, 1), [0, 1, 2]);
    });
  });

  group('removeFromOrder', () {
    test('drops the item', () {
      expect(removeFromOrder([0, 1, 2], 0, 2), [0, 1]);
    });

    test('never drops the current video', () {
      expect(removeFromOrder([0, 1, 2], 1, 1), [0, 1, 2]);
    });
  });

  group('queueTimeLeft', () {
    test('rest of the current video plus the following ones, scaled by speed', () {
      expect(
        queueTimeLeft(
          order: [2, 0, 1],
          current: 0,
          durationsMs: [60000, 30000, 10000],
          currentDuration: const Duration(seconds: 60),
          position: const Duration(seconds: 20),
          rate: 2,
        ),
        const Duration(seconds: 35), // (40 + 30) / 2
      );
    });

    test('null when a following duration is unknown', () {
      expect(
        queueTimeLeft(
          order: [0, 1],
          current: 0,
          durationsMs: [1000, 0],
          currentDuration: const Duration(seconds: 1),
          position: Duration.zero,
          rate: 1,
        ),
        isNull,
      );
      expect(
        queueTimeLeft(
          order: [0, 1],
          current: 0,
          durationsMs: const [],
          currentDuration: const Duration(seconds: 1),
          position: Duration.zero,
          rate: 1,
        ),
        isNull,
      );
    });

    test('on the last video it is just what is left of it', () {
      expect(
        queueTimeLeft(
          order: [0, 1],
          current: 1,
          durationsMs: const [],
          currentDuration: const Duration(seconds: 10),
          position: const Duration(seconds: 4),
          rate: 1,
        ),
        const Duration(seconds: 6),
      );
    });

    test('null while the current duration is not known yet', () {
      expect(
        queueTimeLeft(
          order: [0],
          current: 0,
          durationsMs: const [],
          currentDuration: Duration.zero,
          position: Duration.zero,
          rate: 1,
        ),
        isNull,
      );
    });
  });
}
