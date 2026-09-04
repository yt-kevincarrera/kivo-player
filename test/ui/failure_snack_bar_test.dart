import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/ui/widgets/failure_snack_bar.dart';

import '../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

void main() {
  testWidgets('shows the message with the code and a details action',
      (tester) async {
    await pumpLocalized(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFailureSnackBar(context, KivoOp.delete,
                cause: 'SecurityException: denied'),
            child: const Text('go'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    // Let the SnackBar finish sliding in — mid-animation its action still sits
    // below the test viewport and cannot be tapped.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(find.text('${_l10n.errorDelete} (KV-301)'), findsOneWidget);
    expect(find.textContaining('SecurityException'), findsNothing);

    await tester.tap(find.text(_l10n.errorDetailsAction));
    await tester.pumpAndSettle();

    expect(find.textContaining('SecurityException'), findsOneWidget);
  });
}
