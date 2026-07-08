import '../engine/playback_engine.dart';

/// Heuristic: media_kit doesn't expose mpv's `forced` flag, so treat a track as
/// forced when its title or language says so. Forced subtitle tracks only show
/// forced-narrative lines (often nothing), so they're a poor auto-default.
bool looksForced(MediaTrack t) {
  final s = '${t.title ?? ''} ${t.language ?? ''}'.toLowerCase();
  return s.contains('forced') || s.contains('forzad');
}

/// Picks which subtitle track (if any) should be active when a video opens.
/// Returns null for "no subtitle" — either because [enabledByDefault] is
/// false (the user's last explicit choice), or the video has no tracks.
/// Prefers non-forced tracks; falls back to any track if all are forced.
MediaTrack? selectSubtitleTrack({
  required List<MediaTrack> tracks,
  required bool enabledByDefault,
  required String? preferredLanguage,
}) {
  if (!enabledByDefault) return null;
  if (tracks.isEmpty) return null;
  if (preferredLanguage != null) {
    final byLang = tracks.where((t) => t.language == preferredLanguage).toList();
    if (byLang.isNotEmpty) return _preferNonForced(byLang);
  }
  return _preferNonForced(tracks);
}

/// Prefer non-forced tracks; within the chosen pool, a `default`-flagged track,
/// else the first. Falls back to the full list if every track looks forced.
MediaTrack _preferNonForced(List<MediaTrack> tracks) {
  final nonForced = tracks.where((t) => !looksForced(t)).toList();
  final pool = nonForced.isNotEmpty ? nonForced : tracks;
  for (final t in pool) {
    if (t.isDefault) return t;
  }
  return pool.first;
}

/// Picks which audio track should be active. Unlike subtitles, audio has no
/// "off" state — returns null only when [tracks] is empty.
MediaTrack? selectAudioTrack({
  required List<MediaTrack> tracks,
  required String? preferredLanguage,
}) {
  if (tracks.isEmpty) return null;
  if (preferredLanguage != null) {
    for (final t in tracks) {
      if (t.language == preferredLanguage) return t;
    }
  }
  for (final t in tracks) {
    if (t.isDefault) return t;
  }
  return tracks.first;
}

/// Extracts a language code from a common external-subtitle filename
/// convention like "Movie.en.srt" or "Movie.spa.srt" — the segment right
/// before the extension, if it looks like a short (2-3 letter) language
/// code. Returns null if the filename doesn't follow this pattern.
String? languageFromFilename(String filename) {
  final parts = filename.split('.');
  if (parts.length < 3) return null; // need at least name.lang.ext
  final candidate = parts[parts.length - 2].toLowerCase();
  if (candidate.length < 2 || candidate.length > 3) return null;
  if (!RegExp(r'^[a-z]+$').hasMatch(candidate)) return null;
  return candidate;
}
