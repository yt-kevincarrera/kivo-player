import 'package:permission_handler/permission_handler.dart';
import '../../core/errors/error_log.dart';
import '../../core/errors/kivo_failure.dart';
import '../interfaces/media_permission.dart';

class PermissionHandlerMediaPermission implements MediaPermission {
  PermissionHandlerMediaPermission(this._log);

  final ErrorLog _log;

  // Request both; permission_handler ignores the one not applicable to the OS
  // version (videos = Android 13+ READ_MEDIA_VIDEO; storage = ≤12).
  MediaAccess _combine(PermissionStatus videos, PermissionStatus storage) {
    if (videos.isGranted || storage.isGranted) return MediaAccess.granted;
    if (videos.isLimited) return MediaAccess.limited; // Android 14 partial access
    return MediaAccess.denied;
  }

  /// Polling status is not a failure, so nothing is recorded here.
  @override
  Future<MediaAccess> status() async =>
      _combine(await Permission.videos.status, await Permission.storage.status);

  @override
  Future<MediaAccess> request() async {
    final res = await [Permission.videos, Permission.storage].request();
    final access = _combine(
      res[Permission.videos] ?? PermissionStatus.denied,
      res[Permission.storage] ?? PermissionStatus.denied,
    );
    // A denial the user chose is still worth recording: it is the answer to
    // "why doesn't anything load" weeks later.
    if (access == MediaAccess.denied) {
      _log.record(KivoFailure(KivoOp.mediaAccess,
          'videos=${res[Permission.videos]} storage=${res[Permission.storage]}'));
    }
    return access;
  }
}
