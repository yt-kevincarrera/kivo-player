import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../l10n/l10n.dart';
import '../../../player/library/played.dart';
import '../../../player/open/video_source.dart';
import '../../home/widgets/thumbnail_image.dart';
import '../../widgets/segmented_progress.dart';
import '../state/controls_visibility.dart';
import '../state/queue_strip_state.dart';
import 'queue_card_menu.dart';
import 'queue_info_line.dart';

/// Horizontal, always-with-controls strip of the current queue's thumbnails.
/// Sizes itself to the orientation (smaller in portrait). Tap a card to jump;
/// hold one to drag it elsewhere in the play order, or hold and release in
/// place for its menu (play next / remove). Edits only last this session.
class QueueStrip extends ConsumerStatefulWidget {
  const QueueStrip({super.key});
  @override
  ConsumerState<QueueStrip> createState() => _QueueStripState();
}

class _QueueStripState extends ConsumerState<QueueStrip> {
  final _scroll = ScrollController();
  int? _centered; // last index auto-scrolled to — never fight manual scroll
  static const _gap = 8.0;

  // The hold in flight: the card's queue index and its play-order position
  // when lifted. Where it is dropped tells a move from a menu request.
  int? _held;
  int _heldFrom = -1;
  // The notifiers a hold talks to, captured at lift: a drop, a menu choice
  // or a cancel can land after this strip is gone (a rotation remounts the
  // bottom bar), when `ref` can no longer be used.
  CurrentVideoNotifier? _videos;
  ControlsVisibilityNotifier?
  _holding; // set while this strip holds the controls
  final _cardKeys =
      <int, GlobalKey>{}; // queue index → card, to anchor the menu

  @override
  void dispose() {
    // Never leave the controls held: that provider outlives the player.
    _release();
    _scroll.dispose();
    super.dispose();
  }

  void _hold() {
    if (_holding != null) return;
    final controls = ref.read(controlsVisibleProvider.notifier);
    controls.hold();
    _holding = controls;
  }

  void _release() {
    final h = _holding;
    _holding = null;
    h?.release();
  }

  void _centerOn(
    int index,
    double cardExtent,
    double viewportW, {
    required bool animate,
  }) {
    if (!_scroll.hasClients) return;
    final target = (index * cardExtent - (viewportW - cardExtent) / 2).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if (animate) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  void _onLift(List<int> order, int pos) {
    _held = order[pos];
    _heldFrom = pos;
    _videos = ref.read(currentVideoProvider.notifier);
    _hold();
    if (ref.read(settingsProvider).hapticsOnGestures) {
      HapticFeedback.mediumImpact();
    }
  }

  /// Arrives after the drop animation, possibly once the strip is gone.
  void _onReorder(int from, int to) {
    // ReorderableListView reports [to] as if the card were still in place.
    if (to > from) to--;
    if (to == from) return;
    _videos?.reorder(from, to);
  }

  /// The finger lifted, at insertion slot [to] (counted like [_onReorder]'s).
  void _onDrop(int to) {
    final held = _held;
    _held = null;
    final moved = to != _heldFrom && to != _heldFrom + 1;
    if (held == null || moved) {
      _release();
      return;
    }
    // Measured once the lifted card has been laid out back in place.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _openMenu(held);
      } finally {
        _release();
      }
    });
  }

  /// Every finger left the strip. A drag the system cancelled (notification
  /// shade, a call, a gesture) never reports a drop: let go of it here. Runs
  /// after the drop callbacks of the same pointer event.
  void _afterPointer() {
    if (_held == null) return;
    _held = null;
    _release();
  }

  Future<void> _openMenu(int item) async {
    final videos = _videos;
    final s = videos == null || !mounted
        ? null
        : ref.read(currentVideoProvider);
    final box = _cardKeys[item]?.currentContext?.findRenderObject();
    if (s == null || box is! RenderBox || !box.attached) return;
    final order = s.playOrder;
    final at = order.indexOf(s.index);
    final isNext = at >= 0 && at + 1 < order.length && order[at + 1] == item;
    if (item == s.index) return; // nothing to offer: it is already playing
    final action = await showQueueCardMenu(
      context,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      showPlayNext: !isNext,
      showRemove: true,
      accent: Color(ref.read(settingsProvider).accentColor),
    );
    _apply(action, item, videos!);
  }

  void _apply(QueueCardAction? action, int item, CurrentVideoNotifier n) {
    switch (action) {
      case QueueCardAction.playNext:
        n.playNext(item);
      case QueueCardAction.remove:
        n.remove(item);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentVideoProvider);
    // The strip answers "what comes next", so it follows the EFFECTIVE order:
    // the shuffle permutation or the user's edits when there are any, the
    // natural queue otherwise. Cards are laid out by position in that order;
    // taps, highlights and edits map back to the real queue index.
    final order = session?.playOrder ?? const <int>[];
    if (session == null || order.length <= 1) {
      return const SizedBox.shrink();
    }

    final accent = Color(ref.watch(settingsProvider).accentColor);
    final resume = ref.read(resumeServiceProvider);
    final played = ref.read(playedStoreProvider);
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final cardW = landscape ? 104.0 : 84.0;
    final thumbH = landscape ? 58.0 : 48.0;
    final stripH = thumbH + 20; // room for a 1-line name below
    final index = session.index;
    final currentPos = order.indexOf(index);
    final cardExtent = cardW + _gap;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const QueueInfoLine(),
        SizedBox(
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
                  _centerOn(
                    currentPos,
                    cardExtent,
                    viewportW,
                    animate: !firstShow,
                  );
                });
              }
              return Listener(
                onPointerUp: (_) => scheduleMicrotask(_afterPointer),
                onPointerCancel: (_) => scheduleMicrotask(_afterPointer),
                child: ReorderableListView.builder(
                  scrollController: _scroll,
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  itemCount: order.length,
                  onReorderStart: (pos) => _onLift(order, pos),
                  onReorder: _onReorder,
                  onReorderEnd: _onDrop,
                  proxyDecorator: _lifted,
                  itemBuilder: (context, pos) {
                    final i = order[pos];
                    final active = i == index;
                    final id = i < session.queueIds.length
                        ? session.queueIds[i]
                        : '';
                    final name = i < session.queueNames.length
                        ? session.queueNames[i]
                        : '';
                    final durationMs = i < session.queueDurationsMs.length
                        ? session.queueDurationsMs[i]
                        : 0;
                    final seconds = active
                        ? null
                        : resume.positionFor(name)?.inSeconds;
                    double? progress;
                    if (seconds != null && durationMs > 0) {
                      final f = seconds * 1000 / durationMs;
                      if (f > 0 && f < 0.97) progress = f;
                    }
                    final watched =
                        !active && seconds == null && played.isPlayed(name);
                    final isNext = currentPos >= 0 && pos == currentPos + 1;
                    final l10n = context.l10n;
                    return Padding(
                      // Keyed by uri AND queue index: unique even when a playlist
                      // holds the same video twice (the reorderable list requires
                      // it), and never recycles a card element across a different
                      // video — otherwise the thumbnail AnimatedSwitcher can
                      // cross-fade a neighbour's frame onto a card.
                      key: ValueKey('${session.queue[i]}#$i'),
                      padding: const EdgeInsets.symmetric(horizontal: _gap / 2),
                      child: ReorderableDelayedDragStartListener(
                        index: pos,
                        child: _QueueCard(
                          key: _cardKeys.putIfAbsent(i, GlobalKey.new),
                          width: cardW,
                          thumbH: thumbH,
                          id: id,
                          name: name,
                          active: active,
                          accent: accent,
                          progress: progress,
                          watched: watched,
                          hint: l10n.playerQueueCardHint,
                          actions: active
                              ? const {}
                              : {
                                  if (!isNext)
                                    CustomSemanticsAction(
                                      label: l10n.playerQueuePlayNext,
                                    ): () => _apply(
                                      QueueCardAction.playNext,
                                      i,
                                      ref.read(currentVideoProvider.notifier),
                                    ),
                                  CustomSemanticsAction(
                                    label: l10n.playerQueueRemove,
                                  ): () => _apply(
                                    QueueCardAction.remove,
                                    i,
                                    ref.read(currentVideoProvider.notifier),
                                  ),
                                },
                          onTap: active
                              ? null
                              : () {
                                  ref.read(queueJumpProvider.notifier).state =
                                      i;
                                  ref
                                      .read(controlsVisibleProvider.notifier)
                                      .show();
                                },
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The card while it is being dragged: lifted a little, on a dark plate
  /// with a soft shadow.
  Widget _lifted(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(animation.value);
        return Transform.scale(
          scale: 1 + 0.06 * t,
          child: Material(
            type: MaterialType.transparency,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0C1120).withValues(alpha: 0.9 * t),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5 * t),
                    blurRadius: 14 * t,
                    offset: Offset(0, 4 * t),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class _QueueCard extends StatelessWidget {
  final double width;
  final double thumbH;
  final String id;
  final String name;
  final bool active;
  final Color accent;
  final double? progress;
  final bool watched;
  final String hint;
  final Map<CustomSemanticsAction, VoidCallback> actions;
  final VoidCallback? onTap;
  const _QueueCard({
    super.key,
    required this.width,
    required this.thumbH,
    required this.id,
    required this.name,
    required this.active,
    required this.accent,
    required this.progress,
    required this.watched,
    required this.hint,
    required this.actions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      hint: active ? null : hint,
      customSemanticsActions: actions,
      child: GestureDetector(
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
                    color: active ? accent : Colors.transparent,
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
                          color: accent,
                          padding: const EdgeInsets.symmetric(vertical: 1.5),
                          // Said by the card's selected state already.
                          child: ExcludeSemantics(
                            child: Text(
                              context.l10n.playerQueueNowBadge,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: onAccent(accent),
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      const Center(
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white70,
                          size: 22,
                        ),
                      ),
                    if (progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SegmentedProgress(
                          progress!,
                          accent: accent,
                          unlit: Colors.white.withValues(alpha: 0.18),
                          segments: 12,
                          height: 3,
                        ),
                      ),
                    if (watched)
                      Positioned(
                        top: 3,
                        right: 3,
                        child: Semantics(
                          label: context.l10n.playerQueueWatched,
                          child: Container(
                            padding: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_rounded,
                              size: 10,
                              color: onAccent(accent),
                            ),
                          ),
                        ),
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
                  color: active ? accent : Colors.white.withValues(alpha: 0.6),
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
