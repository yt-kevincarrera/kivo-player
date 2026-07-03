import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/background/audio_only.dart';
import '../../../player/engine/playback_provider.dart';
import '../../../player/open/video_source.dart';

String infoOverlayText(String content, String name, Duration pos, Duration dur) {
  switch (content) {
    case 'name':
      return name;
    case 'remaining':
      return '$name   -${fmtDuration(dur - pos)}';
    case 'name_time':
    default:
      return '$name   ${fmtDuration(pos)} / ${fmtDuration(dur)}';
  }
}

Alignment infoCornerAlignment(String corner) => switch (corner) {
      'tr' => Alignment.topRight,
      'bl' => Alignment.bottomLeft,
      'br' => Alignment.bottomRight,
      _ => Alignment.topLeft,
    };

class InfoOverlay extends ConsumerWidget {
  const InfoOverlay({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // No video in "Solo audio" → the on-screen info overlay is pointless.
    if (!settings.showInfoOverlay || ref.watch(audioOnlyProvider)) {
      return const SizedBox.shrink();
    }
    final name = ref.watch(currentVideoProvider)?.displayName ?? 'Kivo';
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: infoCornerAlignment(settings.infoOverlayCorner),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: _InfoText(name: name, content: settings.infoOverlayContent),
          ),
        ),
      ),
    );
  }
}

// Isolated so only the time text rebuilds on each position tick.
class _InfoText extends ConsumerWidget {
  final String name;
  final String content;
  const _InfoText({required this.name, required this.content});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur = ref.watch(durationProvider).value ?? Duration.zero;
    return Text(
      infoOverlayText(content, name, pos, dur),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        shadows: [Shadow(color: Colors.black, blurRadius: 6)],
      ),
    );
  }
}
