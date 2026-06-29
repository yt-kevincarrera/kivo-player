import 'dart:io';

abstract class FileSystemLister {
  List<String> listFiles(String dir);
}

class IoFileSystemLister implements FileSystemLister {
  @override
  List<String> listFiles(String dir) {
    // An empty dir would resolve to the current working directory; guard so a
    // path with no separator can never silently list unrelated CWD files.
    if (dir.isEmpty) return const [];
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    return d
        .listSync(followLinks: false)
        .whereType<File>()
        .map((f) => f.path)
        .toList();
  }
}
