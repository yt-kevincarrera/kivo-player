import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../vault/vault_providers.dart';
import 'vault_screen.dart';

void openVault(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VaultScreen()));
}

/// Moves [videos] into the Vault. Shows a one-time uninstall warning first.
Future<void> moveToVault(BuildContext context, WidgetRef ref, List<VideoItem> videos) async {
  if (videos.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final settings = ref.read(settingsProvider);
  if (!settings.vaultUninstallWarningShown) {
    await ref.read(settingsProvider.notifier)
        .set(settings.copyWith(vaultUninstallWarningShown: true));
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Antes de ocultar'),
        content: const Text(
            'Los videos del Vault viven dentro de Kivo. Si desinstalas la app se '
            'pierden. Sácalos del Vault para devolverlos a tu galería.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
      ),
    );
  }
  await ref.read(vaultEntriesProvider.notifier).hide(videos);
  messenger.showSnackBar(SnackBar(content: Text('${videos.length} movidos al Vault')));
}
