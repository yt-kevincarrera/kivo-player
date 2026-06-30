import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../widgets/press_bounce.dart';
import 'thumbnail_image.dart';

class VideoTile extends ConsumerWidget {
  final VideoItem video;
  final double? progress; // 0..1 watched, or null
  final bool compact;     // multi-column dense layout
  final VoidCallback onTap;
  const VideoTile({super.key, required this.video, required this.onTap, this.progress, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Color(ref.watch(settingsProvider).accentColor);
    return PressBounce(
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              Hero(tag: 'video-${video.id}', child: ThumbnailImage(video.id)),
              // duration badge
              Positioned(top: 6, right: 6, child: _badge(fmtDuration(Duration(milliseconds: video.durationMs)))),
              // title gradient + text
              Positioned(left: 0, right: 0, bottom: 0, child: Container(
                padding: EdgeInsets.fromLTRB(8, 16, 8, progress != null ? 8 : 6),
                decoration: const BoxDecoration(gradient: LinearGradient(
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent])),
                child: Text(video.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: compact ? 11 : 13, fontWeight: FontWeight.w600)),
              )),
              if (progress != null)
                Positioned(left: 0, right: 0, bottom: 0, child: _SegmentedProgress(progress!, accent)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _badge(String t) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
      child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 9, fontFeatures: [FontFeature.tabularFigures()])));
}

class _SegmentedProgress extends StatelessWidget {
  final double fraction;
  final Color accent;
  const _SegmentedProgress(this.fraction, this.accent);
  @override
  Widget build(BuildContext context) {
    const n = 16;
    final lit = (fraction * n).round();
    return Row(children: [
      for (var i = 0; i < n; i++)
        Expanded(child: Container(
          height: 4, margin: const EdgeInsets.symmetric(horizontal: 0.5),
          color: i < lit ? accent : Colors.white.withValues(alpha: 0.18),
        )),
    ]);
  }
}
