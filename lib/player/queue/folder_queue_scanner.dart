import 'natural_sort.dart';
import 'file_system_lister.dart';

const kVideoExtensions = {
  'mkv', 'mp4', 'avi', 'mov', 'webm', 'flv', 'wmv',
  'm4v', 'mpg', 'mpeg', 'ts', 'm2ts', '3gp', 'ogv',
};

class FolderQueueScanner {
  final FileSystemLister _lister;
  FolderQueueScanner(this._lister);

  List<String> siblingsOf(String filePath) {
    final dir = _dirOf(filePath);
    final files = _lister.listFiles(dir).where(_isVideo).toList();
    files.sort((a, b) => naturalCompare(_baseName(a), _baseName(b)));
    return files;
  }

  bool _isVideo(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0) return false;
    return kVideoExtensions.contains(path.substring(i + 1).toLowerCase());
  }

  String _dirOf(String path) {
    final i = path.replaceAll('\\', '/').lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  String _baseName(String path) {
    final p = path.replaceAll('\\', '/');
    final i = p.lastIndexOf('/');
    return i < 0 ? p : p.substring(i + 1);
  }
}
