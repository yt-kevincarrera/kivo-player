import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../widgets/press_bounce.dart';
import 'thumbnail_image.dart';

class VideoTile extends ConsumerStatefulWidget {
  final VideoItem video;
  final double? progress; // 0..1 watched, or null
  final bool listRow; // true = 1-col list row; false = cover-grid tile
  final void Function(Rect? origin) onTap;
  final String? sizeLabel; // e.g. "49 MB" — shown in list-row meta line
  final bool isNew;
  final VoidCallback? onOptions;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selecting;

  const VideoTile({
    super.key,
    required this.video,
    required this.onTap,
    this.progress,
    this.listRow = false,
    this.sizeLabel,
    this.isNew = false,
    this.onOptions,
    this.onLongPress,
    this.selected = false,
    this.selecting = false,
  });

  @override
  ConsumerState<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends ConsumerState<VideoTile> {
  final GlobalKey _thumbKey = GlobalKey();

  void _handleTap() {
    final box = _thumbKey.currentContext?.findRenderObject() as RenderBox?;
    Rect? origin;
    if (box != null && box.hasSize) {
      final topLeft = box.localToGlobal(Offset.zero);
      origin = topLeft & box.size;
    }
    widget.onTap(origin);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(ref.watch(settingsProvider).accentColor);
    return widget.listRow
        ? _buildListRow(context, accent)
        : _buildCover(context, accent);
  }

  Widget _buildListRow(BuildContext context, Color accent) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: PressBounce(
        onTap: _handleTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              // Left: 168px-wide 16:9 thumbnail with badge + progress
              SizedBox(
                width: 168,
                child: ClipRRect(
                  key: _thumbKey,
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ThumbnailImage(widget.video.id),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: _badge(
                            fmtDuration(
                              Duration(milliseconds: widget.video.durationMs),
                            ),
                          ),
                        ),
                        if (widget.isNew)
                          Positioned(top: 4, left: 4, child: _newBadge(accent)),
                        if (widget.progress != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _SegmentedProgress(
                              widget.progress!,
                              accent,
                              cs,
                            ),
                          ),
                        if (widget.selected)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.28),
                              ),
                            ),
                          ),
                        if (widget.selecting)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: _selectionBadge(accent, widget.selected),
                          ),
                      ],
                    ),
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
                      widget.video.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.sizeLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.sizeLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Far right: options menu icon — has its own onPressed, does not trigger row onTap
              IconButton(
                icon: Icon(
                  Icons.more_vert,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                onPressed: widget.onOptions ?? () {},
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context, Color accent) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: PressBounce(
        onTap: _handleTap,
        child: ClipRRect(
          key: _thumbKey,
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ThumbnailImage(widget.video.id),
                // Duration badge (top-right)
                Positioned(
                  top: 6,
                  right: 6,
                  child: _badge(
                    fmtDuration(
                      Duration(milliseconds: widget.video.durationMs),
                    ),
                  ),
                ),
                // Nuevo badge (top-left)
                if (widget.isNew)
                  Positioned(top: 6, left: 6, child: _newBadge(accent)),
                // Title gradient + text (on-thumbnail text stays white over the dark gradient)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: EdgeInsets.fromLTRB(
                      8,
                      16,
                      8,
                      widget.progress != null ? 8 : 6,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Text(
                      widget.video.name,
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
                if (widget.progress != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _SegmentedProgress(widget.progress!, accent, cs),
                  ),
                if (widget.selected)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                if (widget.selecting)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _selectionBadge(accent, widget.selected),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionBadge(Color accent, bool selected) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? accent : Colors.black.withValues(alpha: 0.35),
      border: Border.all(color: Colors.white, width: 2),
    ),
    child: selected
        ? Icon(Icons.check, size: 14, color: onAccent(accent))
        : null,
  );

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
    ),
  );

  Widget _newBadge(Color accent) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: accent,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      'Nuevo',
      style: TextStyle(
        color: onAccent(accent),
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
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
    return Row(
      children: [
        for (var i = 0; i < n; i++)
          Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 0.5),
              color: i < lit ? accent : cs.onSurface.withValues(alpha: 0.18),
            ),
          ),
      ],
    );
  }
}
