import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/transition/grow_rect.dart';

Widget _harness(double value) => MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GrowFromRect(
          animation: AlwaysStoppedAnimation<double>(value),
          origin: const Rect.fromLTWH(20, 100, 168, 94.5),
          child: const SizedBox.expand(child: ColoredBox(color: Color(0xFF000000))),
        ),
      ),
    );

void main() {
  testWidgets('GrowFromRect is fully transparent at t=0', (tester) async {
    await tester.pumpWidget(_harness(0));
    final op = tester.widget<Opacity>(find.byType(Opacity));
    expect(op.opacity, 0.0);
  });

  testWidgets('GrowFromRect is fully opaque at t=1', (tester) async {
    await tester.pumpWidget(_harness(1));
    final op = tester.widget<Opacity>(find.byType(Opacity));
    expect(op.opacity, 1.0);
  });

  testWidgets('GrowFromRect clips and transforms its child', (tester) async {
    await tester.pumpWidget(_harness(0.5));
    expect(find.byType(ClipRect), findsOneWidget);
    expect(find.byType(Transform), findsOneWidget);
  });
}
