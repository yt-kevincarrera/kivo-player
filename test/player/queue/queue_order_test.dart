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
}
