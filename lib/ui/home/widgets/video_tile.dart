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
  final bool listRow;     // true = 1-col list row; false = cover-grid tile
  final VoidCallback onTap;
  final String? sizeLabel; // e.g. "49 MB" — shown in list-row meta line
  const VideoTile({
    super.key,
    required this.video,
    required this.onTap,
    this.progress,
    this.listRow = false,
    this.sizeLabel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Color(ref.watch(settingsProvider).accentColor);
    return listRow
        ? _buildListRow(context, accent)
        : _buildCover(context, accent);
  }

  Widget _buildListRow(BuildContext context, Color accent) {
    final cs = Theme.of(context).colorScheme;
    return PressBounce(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            // Left: 150px-wide 16:9 thumbnail with badge + progress
            SizedBox(
              width: 150,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(fit: StackFit.expand, children: [
                    Hero(tag: 'libhero-${video.uri}', child: ThumbnailImage(video.id)),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: _badge(fmtDuration(Duration(milliseconds: video.durationMs))),
                    ),
                    if (progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _SegmentedProgress(progress!, accent, cs),
                      ),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Right: title + size label
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    video.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (sizeLabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sizeLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context, Color accent) {
    final cs = Theme.of(context).colorScheme;
    return PressBounce(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            Hero(tag: 'libhero-${video.uri}', child: ThumbnailImage(video.id)),
            // Duration badge
            Positioned(
              top: 6,
              right: 6,
              child: _badge(fmtDuration(Duration(milliseconds: video.durationMs))),
            ),
            // Title gradient + text (on-thumbnail text stays white over the dark gradient)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(8, 16, 8, progress != null ? 8 : 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Text(
                  video.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (progress != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _SegmentedProgress(progress!, accent, cs),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _badge(String t) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        t,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ));
}

class _SegmentedProgress extends StatelessWidget {
  final double fraction;
  final Color accent;
  final ColorScheme cs;
  const _SegmentedProgress(this.fraction, this.accent, this.cs);

  @override
  Widget build(BuildContext context) {
    const n = 16;
    final lit = (fraction * n).round();
    return Row(children: [
      for (var i = 0; i < n; i++)
        Expanded(
          child: Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 0.5),
            color: i < lit ? accent : cs.onSurface.withValues(alpha: 0.18),
          ),
        ),
    ]);
  }
}
