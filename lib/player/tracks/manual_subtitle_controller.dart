import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/settings/settings_provider.dart';
import '../engine/playback_provider.dart';
import '../open/video_source.dart';
import 'subtitle_importer.dart';
import 'subtitle_prefs_store.dart';

/// Loads a subtitle the user picked by hand: copy it somewhere durable, hand
/// it to mpv, and remember it for this video.
class ManualSubtitleController {
  ManualSubtitleController(this._ref);
  final Ref _ref;

  /// Returns false when nothing was loaded — the caller shows KV-502.
  Future<bool> load(String pickedPath) async {
    final session = _ref.read(currentVideoProvider);
    if (session == null) return false;

    final stored = await _ref
        .read(subtitleImporterProvider)
        .importFor(session.resumeKey, pickedPath);
    if (stored == null) return false;

    // A meaningful title, not the app-owned path's videoKey-based name — the
    // track picker would otherwise list the hand-loaded subtitle with no
    // name (a previous review flagged the title-less call as a real gap).
    await _ref
        .read(playbackEngineProvider)
        .setExternalSubtitle(stored, title: basenameOf(pickedPath));

    // Same flag the picker's folder-subtitle path sets. Without it the file
    // plays while "Mostrar subtítulos" reads off, and on the next open
    // applyDefaultTracks turns subtitles off before the prefs block re-adds
    // this very file.
    final settings = _ref.read(settingsProvider);
    if (!settings.subtitlesEnabledByDefault) {
      await _ref
          .read(settingsProvider.notifier)
          .set(settings.copyWith(subtitlesEnabledByDefault: true));
    }

    final store = _ref.read(subtitlePrefsStoreProvider);
    final existing =
        store.forKey(session.resumeKey) ?? const VideoSubtitlePrefs();
    // copyWith, not a fresh record: a delay already set for this video must
    // survive swapping the subtitle file.
    await store.put(session.resumeKey, existing.copyWith(subtitlePath: stored));
    return true;
  }
}

final manualSubtitleProvider =
    Provider<ManualSubtitleController>((ref) => ManualSubtitleController(ref));
