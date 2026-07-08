import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../platform/interfaces/media_indexer.dart';
import '../platform/vault_ops_provider.dart';
import '../player/library/media_index.dart';
import 'vault_auth.dart';
import 'vault_entry.dart';
import 'vault_repository.dart';
import 'vault_store.dart';

/// Overridden in main() with a HiveVaultStore.
final vaultStoreProvider = Provider<VaultStore>((ref) {
  throw UnimplementedError('vaultStoreProvider must be overridden');
});

/// Overridden in main() with a Hive-backed credential store.
final vaultCredentialStoreProvider = Provider<VaultCredentialStore>((ref) {
  throw UnimplementedError('vaultCredentialStoreProvider must be overridden');
});

final vaultAuthProvider =
    Provider<VaultAuth>((ref) => VaultAuth(ref.watch(vaultCredentialStoreProvider)));

final vaultRepositoryProvider = Provider<VaultRepository>((ref) =>
    VaultRepository(ref.watch(vaultStoreProvider), ref.watch(vaultOpsProvider)));

/// Whether the vault is currently unlocked this session. Reset on auto-lock.
final vaultUnlockedProvider = StateProvider<bool>((ref) => false);

class VaultEntriesNotifier extends AsyncNotifier<List<VaultEntry>> {
  VaultRepository get _repo => ref.read(vaultRepositoryProvider);

  @override
  Future<List<VaultEntry>> build() async => _repo.entries;

  Future<void> hide(List<VideoItem> videos) async {
    await _repo.hide(videos);
    state = AsyncData(_repo.entries);
    ref.invalidate(mediaIndexProvider);
  }

  Future<bool> unhide(List<VaultEntry> entries) async {
    final ok = await _repo.unhide(entries);
    state = AsyncData(_repo.entries);
    if (ok) ref.invalidate(mediaIndexProvider);
    return ok;
  }

  Future<bool> deleteForever(List<VaultEntry> entries) async {
    final ok = await _repo.deleteForever(entries);
    state = AsyncData(_repo.entries);
    return ok;
  }
}

final vaultEntriesProvider =
    AsyncNotifierProvider<VaultEntriesNotifier, List<VaultEntry>>(
        VaultEntriesNotifier.new);
