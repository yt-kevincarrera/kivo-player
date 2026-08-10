import 'package:flutter/services.dart';
import '../../core/errors/error_log.dart';
import '../../core/errors/kivo_failure.dart';
import '../interfaces/vault_ops.dart';

class AndroidVaultOps implements VaultOps {
  AndroidVaultOps(this._log);

  final ErrorLog _log;
  static const MethodChannel _channel = MethodChannel('kivo/vault');

  /// A partially successful batch is NOT a failure: one unreadable file must
  /// not cost the user the other twenty-nine. The gap is recorded for later;
  /// only a total failure reaches the user as KV-401.
  @override
  Future<List<Map<String, dynamic>>> hide(List<String> uris) async {
    List<Map<String, dynamic>> hidden;
    try {
      final raw =
          await _channel.invokeMethod<List<dynamic>>('hide', {'uris': uris}) ??
              const [];
      hidden = raw.map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (e) {
      throw _log.record(KivoFailure(KivoOp.vaultHide, e));
    }
    if (uris.isEmpty) return hidden;
    if (hidden.isEmpty) {
      throw _log.record(
          KivoFailure(KivoOp.vaultHide, 'hid 0 of ${uris.length}: $uris'));
    }
    if (hidden.length < uris.length) {
      _log.record(KivoFailure(KivoOp.vaultHide,
          'hid ${hidden.length} of ${uris.length}; requested $uris'));
    }
    return hidden;
  }

  @override
  Future<List<String>> unhide(List<Map<String, dynamic>> entries) async {
    try {
      final raw = await _channel
              .invokeMethod<List<dynamic>>('unhide', {'entries': entries}) ??
          const [];
      return raw.cast<String>();
    } catch (e) {
      throw _log.record(KivoFailure(KivoOp.vaultRestore, e));
    }
  }

  @override
  Future<List<String>> deleteForever(List<String> privatePaths) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
              'deleteForever', {'paths': privatePaths}) ??
          const [];
      return raw.cast<String>();
    } catch (e) {
      throw _log.record(KivoFailure(KivoOp.vaultPurge, e));
    }
  }

  /// Records and returns null: a missing vault thumbnail is cosmetic.
  @override
  Future<Uint8List?> thumbnail(String privatePath) async {
    try {
      return await _channel
          .invokeMethod<Uint8List>('thumbnail', {'path': privatePath});
    } catch (e) {
      _log.record(KivoFailure(KivoOp.thumbnail, e));
      return null;
    }
  }

  /// Records but does not throw: this runs at startup with no UI to catch it.
  @override
  Future<List<Map<String, dynamic>>> migrate() async {
    try {
      final raw =
          await _channel.invokeMethod<List<dynamic>>('migrate') ?? const [];
      return raw.map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (e) {
      _log.record(KivoFailure(KivoOp.vaultRestore, e));
      return const [];
    }
  }
}
