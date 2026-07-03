import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/open/video_source.dart';
import '../../home/widgets/thumbnail_image.dart';
import '../state/controls_visibility.dart';
import '../state/queue_strip_state.dart';

/// Horizontal, always-with-controls strip of the current queue's thumbnails.
/// Sizes itself to the orientation (smaller in portrait). Tap a card to jump.
class QueueStrip extends ConsumerStatefulWidget {
  const QueueStrip({super.key});
  @override
  ConsumerState<QueueStrip> createState() => _QueueStripState();
}

class _QueueStripState extends ConsumerState<QueueStrip> {
  final _scroll = ScrollController();
  int? _centered; // last index auto-scrolled to — never fight manual scroll
  static const _gap = 8.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _centerOn(int index, double cardExtent, double viewportW,
      {required bool animate}) {
    if (!_scroll.hasClients) return;
    final target = (index * cardExtent - (viewportW - cardExtent) / 2)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 340), curve: Curves.easeOutCubic);
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentVideoProvider);
    if (session == null || session.queue.length <= 1) return const SizedBox.shrink();

    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final cardW = landscape ? 104.0 : 84.0;
    final thumbH = landscape ? 58.0 : 48.0;
    final stripH = thumbH + 20; // room for a 1-line name below
    final index = session.index;
    final cardExtent = cardW + _gap;

    return SizedBox(
      height: stripH,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Center on the current card only when the index changes — measured
          // against the REAL viewport width (the Expanded slot in landscape is
          // not a fixed fraction of the screen), so it never fights manual
          // scrolling and lands the active card in the middle. First appearance
          // jumps instantly; later changes (tap-jump, autoplay) glide.
          if (_centered != index) {
            final firstShow = _centered == null;
            _centered = index;
            final viewportW = constraints.maxWidth;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _centerOn(index, cardExtent, viewportW, animate: !firstShow);
            });
          }
          return ListView.builder(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: session.queue.length,
            itemBuilder: (context, i) {
              final active = i == index;
              final id = i < session.queueIds.length ? session.queueIds[i] : '';
              final name = i < session.queueNames.length ? session.queueNames[i] : '';
              return Padding(
                // Keyed by the queue uri so the ListView never recycles a card
                // element across a different video — without this the thumbnail
                // AnimatedSwitcher can cross-fade a neighbour's frame onto a
                // card, making the tapped preview look like a different video.
                key: ValueKey(session.queue[i]),
                padding: EdgeInsets.only(right: i == session.queue.length - 1 ? 0 : _gap),
                child: _QueueCard(
                  width: cardW,
                  thumbH: thumbH,
                  id: id,
                  name: name,
                  active: active,
                  onTap: active
                      ? null
                      : () {
                          ref.read(queueJumpProvider.notifier).state = i;
                          ref.read(controlsVisibleProvider.notifier).show();
                        },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  final double width;
  final double thumbH;
  final String id;
  final String name;
  final bool active;
  final VoidCallback? onTap;
  const _QueueCard({
    required this.width,
    required this.thumbH,
    required this.id,
    required this.name,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: thumbH,
              width: width,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: active ? KivoColors.gold : Colors.transparent,
                  width: 2,
                ),
                color: const Color(0xFF0C1120),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: active ? 1 : 0.6,
                    child: id.isEmpty
                        ? const ColoredBox(color: Color(0xFF1C2A44))
                        : ThumbnailImage(id, fit: BoxFit.cover),
                  ),
                  if (active)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: KivoColors.gold,
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: const Text('AHORA',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Color(0xFF231705),
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5)),
                      ),
                    )
                  else
                    const Center(
                      child: Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 22),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? KivoColors.gold : Colors.white.withValues(alpha: 0.6),
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
