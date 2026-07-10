import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../vault/vault_providers.dart';
import 'vault_screen.dart';

void openVault(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VaultScreen()));
}

/// Moves [videos] into the Vault (a hidden, same-volume folder — an instant
/// rename) and confirms with a single SnackBar.
Future<void> moveToVault(BuildContext context, WidgetRef ref, List<VideoItem> videos) async {
  if (videos.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  await ref.read(vaultEntriesProvider.notifier).hide(videos);
  messenger.showSnackBar(SnackBar(content: Text('${videos.length} movidos al Vault')));
}
