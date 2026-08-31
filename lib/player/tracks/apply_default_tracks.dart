import '../../core/settings/kivo_settings.dart';
import '../../platform/interfaces/subtitle_finder.dart';
import '../engine/playback_engine.dart';
import '../open/video_source.dart';
import 'track_prefs_store.dart';
import 'track_selection.dart';

/// Applies the user's default audio/subtitle choices when a video opens:
/// preferred-language embedded tracks first, then (for library videos with a
/// [VideoSession.folder]) an external subtitle file next to it whose filename
/// encodes the preferred language, then this specific video's remembered
/// subtitle setup (a hand-picked file and/or a timing offset), which wins
/// over everything above. Fire-and-forget; best-effort — a track/finder error
/// must never break playback start.
void applyDefaultTracks({
  required PlaybackEngine engine,
  required KivoSettings settings,
  required VideoSession session,
  required SubtitleFinder subtitleFinder,
  required TrackPrefsStore subtitlePrefs,
}) {
  () async {
    final audioTracks = await engine.audioTracksStream.first.timeout(
      const Duration(seconds: 2), onTimeout: () => const <MediaTrack>[]);
    final audioPick = selectAudioTrack(
      tracks: audioTracks, preferredLanguage: settings.preferredAudioLanguage);
    if (audioPick != null) await engine.setAudioTrack(audioPick.id);

    final subtitleTracks = await engine.subtitleTracksStream.first.timeout(
      const Duration(seconds: 2), onTimeout: () => const <MediaTrack>[]);
    final subtitlePick = selectSubtitleTrack(
      tracks: subtitleTracks,
      enabledByDefault: settings.subtitlesEnabledByDefault,
      preferredLanguage: settings.preferredSubtitleLanguage);
    if (subtitlePick != null) {
      await engine.setSubtitleTrack(subtitlePick.id);
    } else if (settings.subtitlesEnabledByDefault &&
        settings.preferredSubtitleLanguage != null &&
        session.folder != null) {
      try {
        final externals = await subtitleFinder.findNear(session.folder!);
        for (final ext in externals) {
          if (languageFromFilename(ext.displayName) == settings.preferredSubtitleLanguage) {
            await engine.setExternalSubtitle(ext.uri, title: ext.displayName);
            break;
          }
        }
      } catch (_) {
        // Best-effort — native channel errors / empty folder never break start.
      }
    }

    // What this video remembers wins over the language defaults above: the
    // user picked it for this file specifically. The file is loaded before the
    // offset so the delay lands on the track it was measured against.
    var subtitleDelayMs = 0;
    var audioDelayMs = 0;
    try {
      final prefs = subtitlePrefs.forKey(session.resumeKey);
      subtitleDelayMs = prefs?.subtitleDelayMs ?? 0;
      audioDelayMs = prefs?.audioDelayMs ?? 0;
      final path = prefs?.subtitlePath;
      if (path != null) await engine.setExternalSubtitle(path);
    } catch (_) {
      // A corrupted record, or a copy that is gone (storage cleared). Degrade
      // to the embedded tracks already applied rather than failing the open —
      // and leave both offsets at 0 so the resets below still happen.
    }

    // Both unconditional, even with no prefs at all and even for a zero
    // offset: sub-delay and audio-delay are ordinary mpv options, not per-file
    // state, and the engine holds one process-lifetime Player that open()
    // reuses — mpv does not reset them on loadfile. Without this, the previous
    // video's offset silently rides along into a video that has none, while
    // the HUD swears it is zero. Two calls per open, not per tap, so the
    // ANR-sensitive setProperty budget is unchanged.
    try {
      await engine.setSubtitleDelay(subtitleDelayMs / 1000);
    } catch (_) {
      // Best-effort like everything else here: a native failure must not break
      // playback start.
    }
    try {
      await engine.setAudioDelay(audioDelayMs / 1000);
    } catch (_) {
      // Separate try: a failure applying one offset must not skip the other.
    }
  }();
}
