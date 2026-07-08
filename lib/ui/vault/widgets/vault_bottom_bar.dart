import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../vault/vault_entry.dart';
import '../../../vault/vault_providers.dart';
import '../../../vault/vault_selection.dart';

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
              _action(cs.onSurface, Icons.lock_open_outlined, 'Sacar del Vault', enabled ? () async {
                final ok = await ref.read(vaultEntriesProvider.notifier).unhide(chosen);
                sel.clear();
                messenger.showSnackBar(SnackBar(content: Text(
                    ok ? '${chosen.length} devueltos a la galería' : 'No se pudieron sacar todos')));
              } : null),
              _action(cs.error, Icons.delete_forever_outlined, 'Borrar del teléfono', enabled ? () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Borrar del teléfono'),
                    content: Text('¿Borrar ${chosen.length} videos para siempre? No se pueden recuperar.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('Borrar', style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
                    ],
                  ),
                );
                if (ok != true) return;
                final done = await ref.read(vaultEntriesProvider.notifier).deleteForever(chosen);
                sel.clear();
                messenger.showSnackBar(SnackBar(content: Text(
                    done ? '${chosen.length} borrados' : 'No se pudieron borrar todos')));
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
