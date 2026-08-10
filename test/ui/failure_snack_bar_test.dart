import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/ui/widgets/failure_snack_bar.dart';

void main() {
  testWidgets('shows the message with the code and a details action',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFailureSnackBar(context, KivoOp.delete,
                cause: 'SecurityException: denied'),
            child: const Text('go'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    // Let the SnackBar finish sliding in — mid-animation its action still sits
    // below the test viewport and cannot be tapped.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('No pudimos borrar el video (KV-301)'), findsOneWidget);
    expect(find.textContaining('SecurityException'), findsNothing);

    await tester.tap(find.text('Detalles'));
    await tester.pumpAndSettle();

    expect(find.textContaining('SecurityException'), findsOneWidget);
  });
}
