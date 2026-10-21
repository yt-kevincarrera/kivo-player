import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/media_file_ops_provider.dart';
import '../../../player/end_actions/end_actions.dart';
import '../../../player/end_actions/end_flow.dart';
import '../../../player/open/video_source.dart';
import '../state/autoplay_state.dart';

/// Bottom-right corner card shown for 3s (foreground fullscreen only —
/// PlayerScreen keeps this out of the tree in PiP) when a video ended and
/// something is about to happen: autoplay's "Próximo" ([autoplayPendingProvider])
/// or a «Después» action ([afterPendingProvider]). The ring drains over 3s; on
/// completion (or the primary button) it flips the matching confirm provider,
/// which PlayerScreen listens to. "Cancelar" clears it — and the planned
/// trash too: cancelling means nothing happens.
///
/// When the video that ended is going to the trash ([endTrashProvider]) the
/// card says so, with «Conservar» — the moment someone who forgot the mode
/// was on gets to save the file.
class AutoplayOverlay extends ConsumerStatefulWidget {
  const AutoplayOverlay({super.key});
  @override
  ConsumerState<AutoplayOverlay> createState() => _AutoplayOverlayState();
}

class _AutoplayOverlayState extends ConsumerState<AutoplayOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    _ring.addStatusListener(_onRingStatus);
  }

  void _onRingStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _confirm();
  }

  void _confirm() {
    if (ref.read(autoplayPendingProvider) != null) {
      ref.read(autoplayConfirmProvider.notifier).state = true;
    } else if (ref.read(afterPendingProvider) != null) {
      ref.read(afterConfirmProvider.notifier).state = true;
    }
  }

  void _cancel() {
    _ring.stop();
    ref.read(autoplayPendingProvider.notifier).state = null;
    ref.read(afterPendingProvider.notifier).state = null;
    ref.read(endTrashProvider.notifier).state = null;
  }

  @override
  void dispose() {
    _ring.removeStatusListener(_onRingStatus);
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The queue was edited during the countdown (the strip stays usable):
    // count down to whatever is next NOW — or stop if nothing is left.
    ref.listen(currentVideoProvider.select((s) => s?.order), (_, _) {
      if (ref.read(autoplayPendingProvider) == null) return;
      ref.read(autoplayPendingProvider.notifier).state = ref
          .read(currentVideoProvider.notifier)
          .peekNext();
    });
    void onPending(bool before, bool now) {
      if (!before && now) {
        _ring.forward(from: 0);
      } else if (!now) {
        _ring.stop();
      }
    }

    ref.listen(autoplayPendingProvider, (previous, next) {
      if (ref.read(afterPendingProvider) != null) return;
      onPending(previous != null, next != null);
    });
    ref.listen(afterPendingProvider, (previous, next) {
      if (ref.read(autoplayPendingProvider) != null) return;
      onPending(previous != null, next != null);
    });

    final pending = ref.watch(autoplayPendingProvider);
    final after = ref.watch(afterPendingProvider);
    if (pending == null && after == null) {
      if (_ring.status != AnimationStatus.dismissed) _ring.reset();
      return const SizedBox.shrink();
    }
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final trash = ref.watch(endTrashProvider);
    final l10n = context.l10n;
    final label = pending != null
        ? l10n.playerAutoplayNextLabel
        : switch (after!) {
            AfterEnd.closePlayer => l10n.endActionsCountdownClosePlayer,
            AfterEnd.closeApp => l10n.endActionsCountdownCloseApp,
            AfterEnd.screenOff => l10n.endActionsCountdownScreenOff,
            AfterEnd.restart => l10n.endActionsRestart,
            AfterEnd.keepGoing => '',
          };
    final icon = pending != null
        ? Icons.play_arrow_rounded
        : switch (after!) {
            AfterEnd.closePlayer => Icons.close_fullscreen_rounded,
            AfterEnd.closeApp => Icons.power_settings_new_rounded,
            AfterEnd.screenOff => Icons.brightness_low_rounded,
            AfterEnd.restart => Icons.replay_rounded,
            AfterEnd.keepGoing => Icons.play_arrow_rounded,
          };
    final title =
        pending?.displayName ??
        ref.watch(currentVideoProvider)?.displayName ??
        '';

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24, right: 16),
        child: Container(
          width: 290,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(10, 14, 26, 0.92),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 74,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent.withValues(alpha: 0.5)),
                    ),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            color: accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedBuilder(
                    animation: _ring,
                    builder: (context, _) {
                      final secondsLeft = ((1 - _ring.value) * 3).ceil();
                      return SizedBox(
                        width: 34,
                        height: 34,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 34,
                              height: 34,
                              child: CircularProgressIndicator(
                                value: 1 - _ring.value,
                                strokeWidth: 3,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.14,
                                ),
                                valueColor: AlwaysStoppedAnimation(accent),
                              ),
                            ),
                            Text(
                              '$secondsLeft',
                              style: TextStyle(
                                color: accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
              if (trash != null) ...[
                const SizedBox(height: 10),
                _TrashLine(
                  key: const Key('end-trash-line'),
                  accent: accent,
                  text: ref.watch(mediaFileOpsProvider).movesToTrash
                      ? l10n.endActionsCardTrashLine
                      : l10n.endActionsCardDeleteLine,
                  keepLabel: l10n.endActionsKeep,
                  onKeep: () =>
                      ref.read(endTrashProvider.notifier).state = null,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _cancel,
                      child: Text(
                        l10n.commonCancel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: onAccent(accent),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _confirm,
                      child: Text(
                        pending != null
                            ? l10n.playerAutoplayPlayAction
                            : l10n.endActionsNow,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrashLine extends StatelessWidget {
  final Color accent;
  final String text;
  final String keepLabel;
  final VoidCallback onKeep;
  const _TrashLine({
    super.key,
    required this.accent,
    required this.text,
    required this.keepLabel,
    required this.onKeep,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.delete_outline_rounded, size: 16, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: accent,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onKeep,
            child: Text(
              keepLabel,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
