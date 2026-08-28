import 'package:flutter/material.dart';

import '../../core/errors/kivo_failure.dart';
import 'failure_view.dart';

/// The transient counterpart to [FailureView]: friendly copy plus the code,
/// with the technical detail behind an action rather than in the message.
///
/// Takes a [KivoOp] rather than a [KivoFailure] because most call sites only
/// know *which* operation failed — the file-op adapters return statuses, not
/// exceptions.
void showFailureSnackBar(BuildContext context, KivoOp op, {Object? cause}) =>
    showFailureSnackBarOn(ScaffoldMessenger.of(context), context, op,
        cause: cause);

/// Same message, for call sites whose own context is gone by the time the
/// failure is known — a modal sheet that pops on every outcome, typically.
/// Capture the messenger before the await: resolving one from a sheet's
/// context afterwards is either impossible (defunct) or wrong (the SnackBar
/// draws on the route *below* the sheet, where nobody can see it).
///
/// [detailsContext] only has to outlive the popped route and sit under a
/// Navigator — a NavigatorState's own context does both.
void showFailureSnackBarOn(
  ScaffoldMessengerState messenger,
  BuildContext detailsContext,
  KivoOp op, {
  Object? cause,
}) {
  final failure = KivoFailure(op, cause ?? 'sin detalle técnico');
  messenger.showSnackBar(SnackBar(
    content: Text('${failure.message} (${failure.code})'),
    action: SnackBarAction(
      label: 'Detalles',
      onPressed: () => showFailureDetailsSheet(detailsContext, failure),
    ),
  ));
}
