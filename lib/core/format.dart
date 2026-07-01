String fmtDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

String fmtSize(int bytes) {
  final mb = bytes / 1048576;
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
  return '${mb.toStringAsFixed(mb >= 100 ? 0 : 2)} MB';
}

/// True when a video was added within the last 3 days (worth a "Nuevo" badge).
bool isNewVideo(int dateAddedMs, DateTime now) =>
    now.difference(DateTime.fromMillisecondsSinceEpoch(dateAddedMs)).inDays < 3;

String basenameOf(String? path) {
  if (path == null || path.isEmpty) return 'Kivo';
  final p = path.replaceAll('\\', '/');
  final i = p.lastIndexOf('/');
  return i < 0 ? p : p.substring(i + 1);
}
