import 'dart:async';

import '../../core/settings/kivo_settings.dart';
import '../../platform/interfaces/subtitle_finder.dart';
import '../engine/playback_engine.dart';
import '../open/video_source.dart';
import 'subtitle_loader.dart';
import 'track_prefs_store.dart';
import 'track_selection.dart';

/// Applies the user's default audio/subtitle choices when a video opens:
/// preferred-language embedded tracks first, then (for library videos with a
/// [VideoSession.folder]) an external subtitle file next to it whose filename
/// encodes the preferred language, then this specific video's remembered
/// subtitle setup (a hand-picked file and/or a timing offset), which wins
/// over everything above. Best-effort — a track/finder error must never
/// break playback start.
///
/// The returned future completes once everything that touches the AUDIO is
/// written — the track, the audio offset, the audio chain — so a video
/// opened paused can be started after it: written while playing, each of
/// those restarts the audio (a gap you hear) and makes mpv resync the
/// picture (a jump you see). Subtitles carry on in the background.
Future<void> applyDefaultTracks({
  required PlaybackEngine engine,
  required KivoSettings settings,
  required VideoSession session,
  required SubtitleFinder subtitleFinder,
  required TrackPrefsStore subtitlePrefs,
  required SubtitleLoader subtitleLoader,
  required Future<void> Function() applyAudio,
}) async {
  // A new video: whatever external subtitle the last one had is gone.
  subtitleLoader.clear();
  final prefs = () {
    try {
      return subtitlePrefs.forKey(session.resumeKey);
    } catch (_) {
      // A corrupted record: both offsets stay at 0 so the resets still happen.
      return null;
    }
  }();
  try {
    final audioTracks = await engine.loadedAudioTracks();
    final audioPick = selectAudioTrack(
      tracks: audioTracks, preferredLanguage: settings.preferredAudioLanguage);
    if (audioPick != null) await engine.setAudioTrack(audioPick.id);
  } catch (_) {
    // Best-effort.
  }
  // Unconditional, even for 0: audio-delay is an ordinary mpv option that
  // survives loadfile on the one process-lifetime Player — without this the
  // previous video's offset rides along into this one.
  try {
    await engine.setAudioDelay((prefs?.audioDelayMs ?? 0) / 1000);
  } catch (_) {}
  // The audio chain (equalizer, gain, Modo noche, Realzar voces) belongs to
  // AudioPipelineController, which tracks what mpv holds and derives it for
  // this video's track — known by now, so it is written once.
  try {
    await applyAudio();
  } catch (_) {}

  unawaited(() async {

    final subtitleTracks = await engine.subtitleTracksStream.first.timeout(
      const Duration(seconds: 2), onTimeout: () => const <MediaTrack>[]);
    final subtitlePick = selectSubtitleTrack(
      tracks: subtitleTracks,
      enabledByDefault: settings.subtitlesEnabledByDefault,
      preferredLanguage: settings.preferredSubtitleLanguage);
    // Secondary off FIRST, unconditionally: sid and secondary-sid are global
    // mpv options that survive loadfile, and mpv refuses a track already held
    // by the other slot. With the previous video's secondary id still set,
    // picking that id as this video's primary would silently fail (and the
    // secondary pick below would then fail the other way round).
    try {
      await engine.setSecondarySubtitleTrack(null);
    } catch (_) {
      // Best-effort.
    }
    if (subtitlePick != null) {
      await engine.setSubtitleTrack(subtitlePick.id);
    } else if (settings.subtitlesEnabledByDefault &&
        settings.preferredSubtitleLanguage != null &&
        session.folder != null) {
      try {
        final externals = await subtitleFinder.findNear(session.folder!);
        for (final ext in externals) {
          if (languageFromFilename(ext.displayName) == settings.preferredSubtitleLanguage) {
            await subtitleLoader.load(ext.uri,
                title: ext.displayName, resumeKey: session.resumeKey);
            break;
          }
        }
      } catch (_) {
        // Best-effort — native channel errors / empty folder never break start.
      }
    }

    // Already written off above; set only when there is one to show. Off with
    // subtitles off — a lone top line with no bottom one is not what
    // "subtitles off" means.
    try {
      final secondary = settings.subtitlesEnabledByDefault
          ? selectSecondarySubtitleTrack(
              tracks: subtitleTracks,
              language: settings.secondarySubtitleLanguage,
              primaryId: subtitlePick?.id)
          : null;
      if (secondary != null) await engine.setSecondarySubtitleTrack(secondary.id);
    } catch (_) {
      // Best-effort, like everything here.
    }

    // What this video remembers wins over the language defaults above: the
    // user picked it for this file specifically. The file is loaded before the
    // offset so the delay lands on the track it was measured against.
    final subtitleDelayMs = prefs?.subtitleDelayMs ?? 0;
    try {
      final path = prefs?.subtitlePath;
      if (path != null) {
        await subtitleLoader.load(path, resumeKey: session.resumeKey);
      }
    } catch (_) {
      // A corrupted record, or a copy that is gone (storage cleared). Degrade
      // to the embedded tracks already applied rather than failing the open —
      // and leave both offsets at 0 so the resets below still happen.
    }

    // Unconditional, even with no prefs at all and even for a zero offset
    // (audio-delay is written above, before playback): sub-delay is an
    // ordinary mpv option, not per-file
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
  }());
}
