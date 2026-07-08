import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../player/open/video_source.dart';
import '../player/player_route.dart';
import '../../vault/vault_entry.dart';
import '../../vault/vault_providers.dart';
import '../../vault/vault_selection.dart';
import 'vault_gate.dart';
import 'widgets/vault_bottom_bar.dart';
import 'widgets/vault_thumbnail.dart';

class VaultScreen extends ConsumerWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const VaultGate(child: _VaultContent());
  }
}

class _VaultContent extends ConsumerWidget {
  const _VaultContent();

  void _play(BuildContext context, WidgetRef ref, List<VaultEntry> all, int index) {
    final e = all[index];
    ref.read(currentVideoProvider.notifier).open(VideoSession(
          playbackPath: e.privatePath,
          displayName: e.displayName,
          queue: all.map((v) => v.privatePath).toList(),
          queueNames: all.map((v) => v.displayName).toList(),
          index: index,
        ));
    Navigator.of(context, rootNavigator: true).push(playerRoute());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(vaultEntriesProvider).valueOrNull ?? const <VaultEntry>[];
    final selected = ref.watch(vaultSelectionProvider);
    final selecting = selected.isNotEmpty;
    final sel = ref.read(vaultSelectionProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(selecting ? '${selected.length}' : 'Vault'),
        leading: selecting
            ? IconButton(icon: const Icon(Icons.close), onPressed: sel.clear)
            : null,
        actions: selecting ? null : const [_VaultMenu()],
      ),
      bottomNavigationBar: selecting ? const VaultBottomBar() : null,
      body: entries.isEmpty
          ? Center(child: Text('Vault vacío', style: TextStyle(color: cs.onSurfaceVariant)))
          : GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 16 / 10),
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                final isSel = selected.contains(e.privatePath);
                return GestureDetector(
                  onTap: () {
                    if (selecting) {
                      HapticFeedback.selectionClick();
                      sel.toggle(e.privatePath);
                    } else {
                      _play(context, ref, entries, i);
                    }
                  },
                  onLongPress: () {
                    HapticFeedback.selectionClick();
                    sel.toggle(e.privatePath);
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(10), child: VaultThumbnail(path: e.privatePath)),
                      if (isSel)
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: cs.secondary.withValues(alpha: 0.35),
                            border: Border.all(color: cs.secondary, width: 2),
                          ),
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(Icons.check_circle, color: cs.secondary),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _VaultMenu extends ConsumerWidget {
  const _VaultMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final messenger = ScaffoldMessenger.of(context);
    return PopupMenuButton<String>(
      onSelected: (v) async {
        final notifier = ref.read(settingsProvider.notifier);
        if (v == 'hide') {
          await notifier.set(settings.copyWith(vaultEntranceHidden: !settings.vaultEntranceHidden));
          messenger.showSnackBar(SnackBar(
              content: Text(settings.vaultEntranceHidden
                  ? 'Entrada visible en Ajustes'
                  : 'Entrada oculta. Mantén pulsado el título de Videos para entrar.')));
        } else if (v == 'bio') {
          await notifier.set(settings.copyWith(vaultBiometricEnabled: !settings.vaultBiometricEnabled));
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
            value: 'hide', checked: settings.vaultEntranceHidden, child: const Text('Ocultar entrada')),
        CheckedPopupMenuItem(
            value: 'bio', checked: settings.vaultBiometricEnabled, child: const Text('Usar biometría')),
      ],
    );
  }
}
