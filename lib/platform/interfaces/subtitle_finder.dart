class ExternalSubtitle {
  final String uri;
  final String displayName;
  const ExternalSubtitle({required this.uri, required this.displayName});
}

/// Finds subtitle files sitting in the same folder as a library video.
/// Android-only for now (uses MediaStore.Files, unavailable for videos
/// opened outside the library — see VideoSession.folder).
abstract class SubtitleFinder {
  Future<List<ExternalSubtitle>> findNear(String folder);
}
