import 'package:permission_handler/permission_handler.dart';
import '../interfaces/media_permission.dart';

class PermissionHandlerMediaPermission implements MediaPermission {
  // Request both; permission_handler ignores the one not applicable to the OS
  // version (videos = Android 13+ READ_MEDIA_VIDEO; storage = ≤12).
  MediaAccess _combine(PermissionStatus videos, PermissionStatus storage) {
    if (videos.isGranted || storage.isGranted) return MediaAccess.granted;
    if (videos.isLimited) return MediaAccess.limited; // Android 14 partial access
    return MediaAccess.denied;
  }

  @override
  Future<MediaAccess> status() async =>
      _combine(await Permission.videos.status, await Permission.storage.status);

  @override
  Future<MediaAccess> request() async {
    final res = await [Permission.videos, Permission.storage].request();
    return _combine(
      res[Permission.videos] ?? PermissionStatus.denied,
      res[Permission.storage] ?? PermissionStatus.denied,
    );
  }
}
