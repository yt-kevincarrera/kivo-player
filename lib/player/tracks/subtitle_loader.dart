import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../platform/interfaces/subtitle_transcoder.dart';
import '../../platform/subtitle_transcoder_provider.dart';
import '../engine/playback_engine.dart';
import '../engine/playback_provider.dart';
import 'track_prefs_store.dart';

/// The external subtitle currently loaded, for the picker's encoding card.
@immutable
class ActiveExternalSubtitle {
  const ActiveExternalSubtitle({
    required this.resumeKey,
    required this.sourceUri,
    required this.title,
    required this.encoding,
    required this.detected,
    required this.binary,
  });

  final String resumeKey;

  /// What was asked for — a `content://` uri or an app-owned copy's path —
  /// never the converted cache file, so a reload re-reads the original bytes.
  final String sourceUri;
  final String? title;

  /// The charset the file was read as; null when it could not be prepared
  /// (loaded as-is) or is binary.
  final String? encoding;

  /// True when [encoding] was detected, false when the user chose it.
  final bool detected;

  /// A binary format (VobSub): encodings mean nothing for it.
  final bool binary;
}

final activeExternalSubtitleProvider =
    StateProvider<ActiveExternalSubtitle?>((ref) => null);

/// The one way an external subtitle reaches mpv.
///
/// Every file goes through [SubtitleTranscoder] first, because the bundled
/// libmpv cannot detect or convert charsets: anything that is not UTF-8 would
/// otherwise show as garbage for every non-Latin script. A transcoder failure
/// is never fatal — the file is handed to mpv as-is, which is exactly what
/// Kivo did before this existed.
class SubtitleLoader {
  SubtitleLoader({
    required PlaybackEngine engine,
    required SubtitleTranscoder Function() transcoder,
    required TrackPrefsStore prefs,
    required ActiveExternalSubtitle? Function() readActive,
    required void Function(ActiveExternalSubtitle?) writeActive,
  })  : _engine = engine,
        _transcoder = transcoder,
        _prefs = prefs,
        _readActive = readActive,
        _writeActive = writeActive;

  final PlaybackEngine _engine;
  final SubtitleTranscoder Function() _transcoder;
  final TrackPrefsStore _prefs;
  final ActiveExternalSubtitle? Function() _readActive;
  final void Function(ActiveExternalSubtitle?) _writeActive;

  /// Loads [uri] for the video [resumeKey], in that video's chosen encoding
  /// (or detected). [replaceCurrent] swaps out the currently selected track
  /// instead of adding another one.
  Future<void> load(
    String uri, {
    String? title,
    required String resumeKey,
    bool replaceCurrent = false,
  }) async {
    String? chosen;
    try {
      chosen = _prefs.forKey(resumeKey)?.subtitleEncoding;
    } catch (_) {
      chosen = null; // a corrupt record means "automatic", not "no subtitle"
    }
    PreparedSubtitle? prepared;
    try {
      prepared = await _transcoder()
          .prepare(uri, name: title ?? basenameOf(uri), encoding: chosen);
    } catch (e) {
      // The adapter already logged it (KV-502). mpv gets the raw file.
      debugPrint('SubtitleLoader.prepare failed, loading as-is: $e');
    }
    await _engine.setExternalSubtitle(prepared?.uri ?? uri,
        title: title, replaceCurrent: replaceCurrent);
    _writeActive(ActiveExternalSubtitle(
      resumeKey: resumeKey,
      sourceUri: uri,
      title: title,
      encoding: prepared?.encoding,
      detected: prepared?.detected ?? true,
      binary: prepared != null && prepared.encoding == null,
    ));
  }

  /// The picker chose [encoding] (null = automatic) for the active external
  /// subtitle: remember it for this video and reload the file in it.
  Future<void> reloadWithEncoding(String? encoding) async {
    final active = _readActive();
    if (active == null) return;
    final existing = _prefs.forKey(active.resumeKey) ?? const VideoTrackPrefs();
    await _prefs.put(
        active.resumeKey, existing.copyWith(subtitleEncoding: encoding));
    await load(active.sourceUri,
        title: active.title, resumeKey: active.resumeKey, replaceCurrent: true);
  }

  /// No external subtitle showing any more (another video opened, an embedded
  /// track was picked, or subtitles were turned off).
  void clear() => _writeActive(null);
}

final subtitleLoaderProvider = Provider<SubtitleLoader>((ref) => SubtitleLoader(
      engine: ref.read(playbackEngineProvider),
      // Resolved per load, not here: this provider is read on every open, and
      // a harness that never loads an external subtitle must not need it.
      transcoder: () => ref.read(subtitleTranscoderProvider),
      prefs: ref.read(trackPrefsStoreProvider),
      readActive: () => ref.read(activeExternalSubtitleProvider),
      writeActive: (v) =>
          ref.read(activeExternalSubtitleProvider.notifier).state = v,
    ));
