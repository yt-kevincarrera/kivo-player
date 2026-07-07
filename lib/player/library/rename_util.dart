/// Validates a user-entered base name (no extension). Returns the trimmed name,
/// or null if empty or containing a path separator.
String? sanitizeRenameTarget(String input) {
  final t = input.trim();
  if (t.isEmpty) return null;
  if (t.contains('/') || t.contains('\\')) return null;
  return t;
}

/// Splits a file name into base and extension. [ext] includes the leading dot
/// (e.g. '.mp4'), or is '' when there's no extension. A name that is only a
/// leading dot (e.g. '.hidden') is treated as all-base, no extension.
({String base, String ext}) splitNameExt(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0) return (base: fileName, ext: '');
  return (base: fileName.substring(0, dot), ext: fileName.substring(dot));
}
