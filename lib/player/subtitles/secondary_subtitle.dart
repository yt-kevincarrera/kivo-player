import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_provider.dart';
import '../engine/playback_engine.dart';
import '../engine/playback_provider.dart';
import 'subtitle_render.dart';

/// Bumped on every pick, so a picker showing the choice rebuilds even when
/// the remembered language did not change (e.g. picking "Ninguno" twice).
final secondarySubtitleRevisionProvider = StateProvider<int>((ref) => 0);

/// Tracks that can be the secondary: text only (mpv would draw a picture one
/// over the primary), never the primary itself.
///
/// [primaryMpvId] is mpv's own number for the primary: an external primary
/// is reported by media_kit under its uri, but listed by mpv under a number,
/// and without it the primary would be offered as its own secondary.
List<MediaTrack> secondaryCandidates(
        List<MediaTrack> tracks, MediaTrack? primary, {String? primaryMpvId}) =>
    tracks
        .where((t) =>
            t.id != primary?.id &&
            t.id != primaryMpvId &&
            !isBitmapSubtitle(t.codec))
        .toList();

/// Turns the secondary off without forgetting its language — for when the
/// primary is switched off, or takes over the secondary's own track.
Future<void> clearSecondarySubtitle(WidgetRef ref) async {
  await ref.read(playbackEngineProvider).setSecondarySubtitleTrack(null);
  ref.read(secondarySubtitleRevisionProvider.notifier).state++;
}

/// The user picked [track] (null = none) as the secondary subtitle: show it
/// now, and remember its language so the next video opens with it too.
Future<void> pickSecondarySubtitle(WidgetRef ref, MediaTrack? track) async {
  await ref.read(playbackEngineProvider).setSecondarySubtitleTrack(track?.id);
  final s = ref.read(settingsProvider);
  // A track with no language can be shown, but not remembered: there would
  // be nothing to look for on the next video.
  final lang = track?.language;
  if (track == null || lang != null) {
    await ref
        .read(settingsProvider.notifier)
        .set(s.copyWith(secondarySubtitleLanguage: lang));
  }
  ref.read(secondarySubtitleRevisionProvider.notifier).state++;
}
