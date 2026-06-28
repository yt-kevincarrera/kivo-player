import 'dart:io';

abstract class FileSystemLister {
  List<String> listFiles(String dir);
}

class IoFileSystemLister implements FileSystemLister {
  @override
  List<String> listFiles(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    return d
        .listSync(followLinks: false)
        .whereType<File>()
        .map((f) => f.path)
        .toList();
  }
}
