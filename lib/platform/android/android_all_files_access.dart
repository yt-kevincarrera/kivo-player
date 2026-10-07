import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../interfaces/all_files_access.dart';

class AndroidAllFilesAccess implements AllFilesAccess {
  static const MethodChannel _channel = MethodChannel('kivo/media');

  @override
  Future<bool> isGranted() async =>
      (await Permission.manageExternalStorage.status).isGranted;

  /// Opens Android's own all-files-access page through MainActivity, not
  /// permission_handler: that one answers "granted" without opening anything
  /// once the permission is on, which left the Ajustes row dead and the
  /// permission impossible to revoke from Kivo. Null back means the page
  /// doesn't exist (below Android 11), where permission_handler is right.
  @override
  Future<bool> request() async {
    final granted = await _channel.invokeMethod<bool>('openAllFilesAccess');
    if (granted != null) return granted;
    return (await Permission.manageExternalStorage.request()).isGranted;
  }
}
