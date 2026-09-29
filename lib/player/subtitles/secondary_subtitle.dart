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
List<MediaTrack> secondaryCandidates(
        List<MediaTrack> tracks, MediaTrack? primary) =>
    tracks
        .where((t) => t.id != primary?.id && !isBitmapSubtitle(t.codec))
        .toList();

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
