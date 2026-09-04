import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/ui/widgets/failure_view.dart';

import '../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

void main() {
  const failure = KivoFailure(KivoOp.libraryScan, 'no such column relative_path');

  testWidgets('shows the friendly message and the code', (tester) async {
    await pumpLocalized(tester, const Scaffold(body: FailureView(failure: failure)));

    expect(find.text(_l10n.errorLibraryScan), findsOneWidget);
    expect(find.text('KV-201'), findsOneWidget);
  });

  testWidgets('hides the technical detail until it is asked for', (tester) async {
    await pumpLocalized(tester, const Scaffold(body: FailureView(failure: failure)));

    expect(find.textContaining('relative_path'), findsNothing);

    await tester.tap(find.text(_l10n.errorDetailsSheetAction));
    await tester.pumpAndSettle();

    expect(find.textContaining('relative_path'), findsOneWidget);
  });

  testWidgets('offers a retry when one is given', (tester) async {
    var retried = 0;
    await pumpLocalized(
        tester, Scaffold(body: FailureView(failure: failure, onRetry: () => retried++)));

    await tester.tap(find.text(_l10n.errorRetryAction));
    expect(retried, 1);
  });

  testWidgets('omits retry when none is given', (tester) async {
    await pumpLocalized(tester, const Scaffold(body: FailureView(failure: failure)));
    expect(find.text(_l10n.errorRetryAction), findsNothing);
  });

  testWidgets('an unknown error still gets a message and a code', (tester) async {
    await pumpLocalized(
        tester, Scaffold(body: FailureView.from(StateError('kaboom internals'))));

    expect(find.textContaining('kaboom internals'), findsNothing);
    expect(find.textContaining('KV-'), findsOneWidget);
  });
}
