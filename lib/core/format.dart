String fmtDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

String basenameOf(String? path) {
  if (path == null || path.isEmpty) return 'Kivo';
  final p = path.replaceAll('\\', '/');
  final i = p.lastIndexOf('/');
  return i < 0 ? p : p.substring(i + 1);
}
