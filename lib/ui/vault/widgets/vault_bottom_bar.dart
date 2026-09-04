import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/kivo_failure.dart';
import '../../../l10n/l10n.dart';
import '../../../vault/vault_entry.dart';
import '../../../vault/vault_providers.dart';
import '../../../vault/vault_selection.dart';
import '../../widgets/failure_snack_bar.dart';

/// Bottom action bar shown while selecting inside the Vault. Mirrors
/// SelectionBottomBar (thumb-reachable). Delete-forever keeps a confirmation
/// because it is irreversible.
class VaultBottomBar extends ConsumerWidget {
  const VaultBottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(vaultSelectionProvider);
    final sel = ref.read(vaultSelectionProvider.notifier);
    final entries = ref.watch(vaultEntriesProvider).valueOrNull ?? const <VaultEntry>[];
    final chosen = entries.where((e) => selected.contains(e.privatePath)).toList();
    final cs = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final enabled = chosen.isNotEmpty;
    final l10n = context.l10n;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _action(cs.onSurface, Icons.lock_open_outlined, l10n.vaultTakeOutAction, enabled ? () async {
                final bool ok;
                try {
                  ok = await ref.read(vaultEntriesProvider.notifier).unhide(chosen);
                } on KivoFailure catch (f) {
                  sel.clear();
                  if (context.mounted) {
                    showFailureSnackBar(context, f.op, cause: f.cause);
                  }
                  return;
                }
                sel.clear();
                messenger.showSnackBar(SnackBar(content: Text(
                    ok ? l10n.vaultTakeOutSuccessSnackbar(chosen.length) : l10n.vaultTakeOutFailedPartial)));
              } : null),
              _action(cs.error, Icons.delete_forever_outlined, l10n.vaultDeleteForeverAction, enabled ? () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(l10n.vaultDeleteForeverAction),
                    content: Text(l10n.vaultDeleteForeverConfirmMessage(chosen.length)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.commonCancel)),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(l10n.commonDelete, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
                    ],
                  ),
                );
                if (ok != true) return;
                final bool done;
                try {
                  done = await ref.read(vaultEntriesProvider.notifier).deleteForever(chosen);
                } on KivoFailure catch (f) {
                  sel.clear();
                  if (context.mounted) {
                    showFailureSnackBar(context, f.op, cause: f.cause);
                  }
                  return;
                }
                sel.clear();
                messenger.showSnackBar(SnackBar(content: Text(
                    done ? l10n.vaultDeleteForeverSuccessSnackbar(chosen.length) : l10n.vaultDeleteForeverFailedPartial)));
              } : null),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(Color color, IconData icon, String label, VoidCallback? onTap) {
    final c = onTap == null ? color.withValues(alpha: 0.4) : color;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: c),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 11, color: c)),
          ],
        ),
      ),
    );
  }
}
