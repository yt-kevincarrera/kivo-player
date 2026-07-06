import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/sleep/sleep_timer.dart';

/// Bottom toast shown during the sleep timer's 10s warning window, over the
/// fade-out. ✕ dismisses only the toast for this warning cycle; the countdown
/// and fade continue. Positioned like ResumePrompt (bottom-centered capsule).
class SleepWarningToast extends ConsumerStatefulWidget {
  const SleepWarningToast({super.key});
  @override
  ConsumerState<SleepWarningToast> createState() => _SleepWarningToastState();
}

class _SleepWarningToastState extends ConsumerState<SleepWarningToast> {
  int _dismissedCycle = -1;

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(sleepTimerProvider);
    if (st == null || !st.warning || st.cycle == _dismissedCycle) {
      return const SizedBox.shrink();
    }
    final n = ref.read(sleepTimerProvider.notifier);
    final secondsLeft = st.remaining.inSeconds.clamp(0, 10);
    final accent = Color(ref.watch(settingsProvider).accentColor);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 96),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.bedtime_outlined, size: 14, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'Pausando en ',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                        children: [
                          TextSpan(
                            text: fmtDuration(st.remaining),
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _dismissedCycle = st.cycle),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded,
                          size: 15, color: Colors.white.withValues(alpha: 0.42)),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 8),
                child: Row(
                  children: [
                    for (var i = 0; i < 10; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i == 9 ? 0 : 3),
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: i < secondsLeft
                                  ? accent
                                  : Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => n.cancel(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Text('Desactivar',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => n.extend(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text('Extender',
                          style: TextStyle(
                              color: onAccent(accent),
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5)),
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
