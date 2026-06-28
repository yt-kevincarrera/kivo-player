import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/ui/home/open_screen.dart';

void main() {
  testWidgets('OpenScreen renders without crashing', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: OpenScreen())),
    );
    expect(find.byType(OpenScreen), findsOneWidget);
  });
}
