import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/player_route.dart';
import 'package:kivo_player/ui/player/transition/grow_rect.dart';

/// A minimal fake [Animation] whose status/value can be set directly,
/// without needing an [AnimationController]/[TickerProvider].
class _FakeAnimation extends Animation<double> {
  _FakeAnimation(this.status, {this.value = 0.0});

  @override
  AnimationStatus status;

  @override
  double value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  void addStatusListener(AnimationStatusListener listener) {}

  @override
  void removeStatusListener(AnimationStatusListener listener) {}
}

void main() {
  const child = SizedBox(key: Key('child'));
  const originRect = Rect.fromLTWH(20, 100, 168, 94.5);

  testWidgets('completed status returns the bare child, regardless of originRect', (tester) async {
    late Widget result;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          result = playerTransition(
            context,
            _FakeAnimation(AnimationStatus.completed),
            originRect,
            child,
          );
          return const SizedBox();
        },
      ),
    );
    expect(identical(result, child), isTrue);
  });

  testWidgets('completed status returns the bare child when originRect is null', (tester) async {
    late Widget result;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          result = playerTransition(
            context,
            _FakeAnimation(AnimationStatus.completed),
            null,
            child,
          );
          return const SizedBox();
        },
      ),
    );
    expect(identical(result, child), isTrue);
  });

  testWidgets('reverse status with a non-null originRect still fades (never flies back to the tile)',
      (tester) async {
    late Widget result;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          result = playerTransition(
            context,
            _FakeAnimation(AnimationStatus.reverse, value: 0.5),
            originRect,
            child,
          );
          return const SizedBox();
        },
      ),
    );
    expect(result, isA<FadeTransition>());
    expect(result, isNot(isA<GrowFromRect>()));
  });

  testWidgets('null originRect with forward status fades', (tester) async {
    late Widget result;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          result = playerTransition(
            context,
            _FakeAnimation(AnimationStatus.forward, value: 0.5),
            null,
            child,
          );
          return const SizedBox();
        },
      ),
    );
    expect(result, isA<FadeTransition>());
  });

  testWidgets('non-null originRect with forward status grows from the rect', (tester) async {
    late Widget result;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          result = playerTransition(
            context,
            _FakeAnimation(AnimationStatus.forward, value: 0.5),
            originRect,
            child,
          );
          return const SizedBox();
        },
      ),
    );
    expect(result, isA<GrowFromRect>());
  });
}
