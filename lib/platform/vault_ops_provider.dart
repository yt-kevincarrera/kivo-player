import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/vault_ops.dart';

/// Overridden in main() with AndroidVaultOps.
final vaultOpsProvider = Provider<VaultOps>((ref) {
  throw UnimplementedError('vaultOpsProvider must be overridden');
});
