import '../../core/settings/kivo_settings.dart';
import '../../platform/interfaces/subtitle_finder.dart';
import '../engine/playback_engine.dart';
import '../open/video_source.dart';
import 'track_selection.dart';

/// Applies the user's default audio/subtitle choices when a video opens:
/// preferred-language embedded tracks first, then (for library videos with a
/// [VideoSession.folder]) an external subtitle file next to it whose filename
/// encodes the preferred language. Fire-and-forget; best-effort — a track/finder
/// error must never break playback start.
void applyDefaultTracks({
  required PlaybackEngine engine,
  required KivoSettings settings,
  required VideoSession session,
  required SubtitleFinder subtitleFinder,
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
  }();
}
