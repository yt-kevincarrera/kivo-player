import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../player/control/player_controller.dart';
import '../speed/speed_panel.dart';
import '../state/controls_visibility.dart';
import '../state/aspect_state.dart';
import '../state/flash_state.dart';
import '../state/lock_state.dart';
import '../state/orientation_state.dart';
import 'seek_bar.dart';
import '../seek/seek_preview_bubble.dart';
import '../queue/queue_strip.dart';
import '../../../player/open/video_source.dart';

class BottomBar extends ConsumerWidget {
  const BottomBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final rate = ref.watch(rateProvider);
    final mode = ref.watch(aspectModeProvider);
    final hasQueue = (ref.watch(currentVideoProvider)?.queue.length ?? 0) > 1;
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    const seek = Stack(
      clipBehavior: Clip.none,
      children: [
        SeekBar(),
        Positioned(
          left: 0, right: 0, bottom: 28, // sit above the bar
          child: SeekPreviewBubble(),
        ),
      ],
    );

    final l10n = context.l10n;

    // Tool buttons (unchanged behavior), reused in both layouts.
    final tools = <Widget>[
      Tooltip(
        message: l10n.playerSpeedTooltip,
        child: TextButton(
          onPressed: () => showSpeedPanel(context),
          child: Text('${rate.toStringAsFixed(2)}x',
              style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
        ),
      ),
      IconButton(
        color: Colors.white,
        tooltip: l10n.playerLockScreenTooltip,
        icon: KivoIcon(KivoIcons.lock, size: 24, color: Colors.white),
        onPressed: () {
          ref.read(lockProvider.notifier).lock();
          ref.read(controlsVisibleProvider.notifier).hide();
        },
      ),
      IconButton(
        color: Colors.white,
        tooltip: l10n.playerAspectRatioTooltip,
        icon: KivoIcon(aspectIconFor(mode), size: 24, color: Colors.white),
        onPressed: () {
          ref.read(aspectModeProvider.notifier).cycle();
          ref.read(flashProvider.notifier).show(
                aspectLabelFor(l10n, ref.read(aspectModeProvider)),
              );
        },
      ),
      IconButton(
        color: Colors.white,
        tooltip: l10n.playerRotateTooltip,
        icon: KivoIcon(KivoIcons.rotate, size: 24, color: Colors.white),
        onPressed: () => ref.read(orientationProvider.notifier).cycle(),
      ),
    ];

    final Widget controlsArea;
    if (hasQueue && landscape) {
      // Half/half row: strip left, tool cluster right.
      controlsArea = Row(
        children: [
          const Expanded(child: QueueStrip()),
          const SizedBox(width: 16),
          ...tools,
          // Pull the tool cluster a touch off the right edge (and give the
          // strip slightly less width) so the row doesn't feel edge-crowded.
          const SizedBox(width: 20),
        ],
      );
    } else if (hasQueue) {
      // Portrait: compact strip above the tools row.
      controlsArea = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const QueueStrip(),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: tools),
        ],
      );
    } else {
      controlsArea = Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: tools);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [seek, controlsArea],
    );
  }
}
