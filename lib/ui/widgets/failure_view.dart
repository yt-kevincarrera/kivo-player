import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors/kivo_failure.dart';
import '../../l10n/l10n.dart';
import 'failure_l10n.dart';

/// The full-screen failure state: friendly message, quotable code, and the
/// technical detail only where the user asked for it.
class FailureView extends StatelessWidget {
  const FailureView({super.key, required this.failure, this.onRetry});

  /// Total over `Object` — Riverpod's `AsyncValue.error` gives us no guarantees,
  /// and an error with no code would be the very hole this closes.
  factory FailureView.from(Object error, {VoidCallback? onRetry}) => FailureView(
        failure:
            error is KivoFailure ? error : KivoFailure(KivoOp.unknown, error),
        onRetry: onRetry,
      );

  final KivoFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              failureMessage(l10n, failure.op),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              failure.code,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onRetry != null) ...[
                  TextButton(
                    onPressed: onRetry,
                    child: Text(l10n.errorRetryAction,
                        style: TextStyle(color: cs.secondary)),
                  ),
                  const SizedBox(width: 4),
                ],
                TextButton(
                  onPressed: () => showFailureDetailsSheet(context, failure),
                  child: Text(l10n.errorDetailsSheetAction,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The one place raw technical text is rendered.
Future<void> showFailureDetailsSheet(BuildContext context, KivoFailure failure) {
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: cs.surfaceContainerHighest,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(failure.code,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.secondary)),
              ),
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 19),
                color: cs.onSurfaceVariant,
                onPressed: () => _copyDetail(sheetContext, failure),
              ),
            ]),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 260),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: cs.surface, borderRadius: BorderRadius.circular(10)),
              child: SingleChildScrollView(
                child: SelectableText(
                  failure.detail,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      height: 1.4,
                      color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _copyDetail(BuildContext context, KivoFailure failure) async {
  await Clipboard.setData(
      ClipboardData(text: '${failure.code}\n${failure.detail}'));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(context.l10n.errorDetailCopiedSnackbar)));
}
