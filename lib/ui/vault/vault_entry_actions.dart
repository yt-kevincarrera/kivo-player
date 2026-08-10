import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/kivo_failure.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../vault/vault_providers.dart';
import '../widgets/failure_snack_bar.dart';
import 'vault_screen.dart';

void openVault(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VaultScreen()));
}

/// Moves [videos] into the Vault (a hidden, same-volume folder — an instant
/// rename) and confirms with a single SnackBar.
Future<void> moveToVault(BuildContext context, WidgetRef ref, List<VideoItem> videos) async {
  if (videos.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(vaultEntriesProvider.notifier).hide(videos);
  } on KivoFailure catch (f) {
    // Nothing was hidden at all — a partial batch does not throw, it just
    // returns fewer entries and logs the gap.
    if (context.mounted) showFailureSnackBar(context, f.op, cause: f.cause);
    return;
  }
  messenger.showSnackBar(SnackBar(content: Text('${videos.length} movidos al Vault')));
}
