import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/widgets/swipe_dismiss_toast.dart';

void main() {
  Future<List<int>> pump(WidgetTester tester,
      {Duration autoHide = const Duration(seconds: 4)}) async {
    final dismissed = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SwipeDismissToast(
            autoHide: autoHide,
            onDismissed: () => dismissed.add(1),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('hola'),
            ),
          ),
        ),
      ),
    ));
    return dismissed;
  }

  testWidgets('hides by itself after autoHide, once', (tester) async {
    final d = await pump(tester);
    await tester.pump(const Duration(milliseconds: 3900));
    expect(d, isEmpty);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 250));
    expect(d, [1]);
    await tester.pump(const Duration(seconds: 5));
    expect(d, [1]);
  });

  testWidgets('a long swipe up dismisses it', (tester) async {
    final d = await pump(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.timedDrag(find.text('hola'), const Offset(0, -100),
        const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 300));
    expect(d, [1]);
  });

  testWidgets('a long swipe sideways dismisses it too', (tester) async {
    final d = await pump(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.timedDrag(find.text('hola'), const Offset(-100, 0),
        const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 300));
    expect(d, [1]);
  });

  testWidgets('a quick flick dismisses it even if short', (tester) async {
    final d = await pump(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.fling(find.text('hola'), const Offset(48, 0), 1500,
        frameInterval: const Duration(milliseconds: 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(d, [1]);
  });

  testWidgets('a short slow drag springs back and the timer starts over',
      (tester) async {
    final d = await pump(tester);
    await tester.pump(const Duration(milliseconds: 3000));
    final before = tester.getCenter(find.text('hola'));
    await tester.timedDrag(find.text('hola'), const Offset(40, 0),
        const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(d, isEmpty);
    expect(tester.getCenter(find.text('hola')), before);
    // Started over on release: 4 s from there, not from the first show.
    await tester.pump(const Duration(milliseconds: 3000));
    expect(d, isEmpty);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 250)); // exit animation
    expect(d, [1]);
  });
}
