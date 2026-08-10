import 'package:flutter/material.dart';

import '../../core/errors/kivo_failure.dart';
import 'failure_view.dart';

/// The transient counterpart to [FailureView]: friendly copy plus the code,
/// with the technical detail behind an action rather than in the message.
///
/// Takes a [KivoOp] rather than a [KivoFailure] because most call sites only
/// know *which* operation failed — the file-op adapters return statuses, not
/// exceptions.
void showFailureSnackBar(BuildContext context, KivoOp op, {Object? cause}) {
  final failure = KivoFailure(op, cause ?? 'sin detalle técnico');
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('${failure.message} (${failure.code})'),
    action: SnackBarAction(
      label: 'Detalles',
      onPressed: () => showFailureDetailsSheet(context, failure),
    ),
  ));
}
