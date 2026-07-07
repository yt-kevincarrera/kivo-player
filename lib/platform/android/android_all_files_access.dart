import 'package:permission_handler/permission_handler.dart';
import '../interfaces/all_files_access.dart';

class AndroidAllFilesAccess implements AllFilesAccess {
  @override
  Future<bool> isGranted() async =>
      (await Permission.manageExternalStorage.status).isGranted;

  @override
  Future<bool> request() async =>
      (await Permission.manageExternalStorage.request()).isGranted;
}
