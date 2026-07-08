import 'package:flutter/services.dart';
import '../interfaces/vault_ops.dart';

class AndroidVaultOps implements VaultOps {
  static const MethodChannel _channel = MethodChannel('kivo/vault');

  @override
  Future<List<Map<String, dynamic>>> hide(List<String> uris) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('hide', {'uris': uris}) ?? const [];
      return raw.map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<bool> unhide(List<String> privatePaths) async {
    try {
      final s = await _channel.invokeMethod<String>('unhide', {'paths': privatePaths});
      return s == 'ok';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> deleteForever(List<String> privatePaths) async {
    try {
      final s = await _channel.invokeMethod<String>('deleteForever', {'paths': privatePaths});
      return s == 'ok';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List?> thumbnail(String privatePath) async {
    try {
      return await _channel.invokeMethod<Uint8List>('thumbnail', {'path': privatePath});
    } catch (_) {
      return null;
    }
  }
}
