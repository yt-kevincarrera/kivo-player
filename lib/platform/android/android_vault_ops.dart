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
  Future<List<String>> unhide(List<String> privatePaths) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('unhide', {'paths': privatePaths}) ?? const [];
      return raw.cast<String>();
    } catch (_) {
      return const <String>[];
    }
  }

  @override
  Future<List<String>> deleteForever(List<String> privatePaths) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('deleteForever', {'paths': privatePaths}) ?? const [];
      return raw.cast<String>();
    } catch (_) {
      return const <String>[];
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
