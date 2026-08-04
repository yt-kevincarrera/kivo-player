import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/loop/ab_loop.dart';
import '../sleep/sleep_timer_panel.dart';
import '../state/controls_visibility.dart';

/// Mini menu behind the top bar's "Más opciones" button. The A-B loop entry
/// joins this menu in 3c.
Future<void> showMoreMenu(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Consumer(
          builder: (_, sheetRef, __) {
            final loop = sheetRef.watch(abLoopProvider);
            final loopSubtitle = switch (loop?.phase) {
              null => 'Repetir un fragmento del video',
              AbLoopPhase.armedA || AbLoopPhase.armedB => 'Marcando…',
              AbLoopPhase.active =>
                'Activo · ${fmtDuration(loop!.a!)}–${fmtDuration(loop.b!)}',
            };
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                _MenuRow(
                  icon: Icons.bedtime_outlined,
                  title: 'Temporizador de apagado',
                  subtitle: 'Detener la reproducción automáticamente',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    showSleepTimerPanel(context, ref,
                        onBack: () => showMoreMenu(context, ref));
                  },
                ),
                const SizedBox(height: 8),
                _MenuRow(
                  icon: Icons.repeat_rounded,
                  title: 'Bucle A-B',
                  subtitle: loopSubtitle,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    if (loop == null) {
                      ref.read(abLoopProvider.notifier).begin();
                      // Chip lives in the controls overlay — make sure it's visible.
                      ref.read(controlsVisibleProvider.notifier).show();
                    } else {
                      ref.read(abLoopProvider.notifier).cancel();
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _MenuRow({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF182036),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: Colors.white70),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(subtitle,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.42), fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white.withValues(alpha: 0.42)),
          ],
        ),
      ),
    );
  }
}
