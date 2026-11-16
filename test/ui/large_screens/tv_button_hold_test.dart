import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/tv/tv_focusable.dart';
import 'package:kivo_player/ui/tv/tv_input_mode.dart';
import '../../helpers/pump_app.dart';

void main() {
  testWidgets('holding OK activates a TV button once, until it is released', (
    t,
  ) async {
    var presses = 0;
    await pumpLocalized(
      t,
      Scaffold(
        body: TvButton(
          label: 'Play',
          autofocus: true,
          onPressed: () => presses++,
        ),
      ),
    );
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.select);
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    expect(presses, 1);
    await t.sendKeyUpEvent(LogicalKeyboardKey.select);
    await t.sendKeyEvent(LogicalKeyboardKey.select);
    expect(presses, 2);
    await t.pump(const Duration(milliseconds: 200));
  });

  testWidgets(
    'TV scope also consumes repeated OK on shared Material controls',
    (t) async {
      var presses = 0;
      await pumpLocalized(
        t,
        Scaffold(
          body: TvRemoteShortcuts(
            child: TextButton(
              autofocus: true,
              onPressed: () => presses++,
              child: const Text('Options'),
            ),
          ),
        ),
      );
      await t.pump();
      await t.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      expect(presses, 1);
      await t.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(presses, 2);
      await t.pump(const Duration(milliseconds: 200));
    },
  );
}
