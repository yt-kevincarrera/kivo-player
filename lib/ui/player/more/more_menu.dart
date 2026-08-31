import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/engine/playback_engine.dart';
import '../../../player/engine/playback_provider.dart';
import '../../../core/errors/kivo_failure.dart';
import '../../../player/capture/frame_capture_controller.dart';
import '../../../player/loop/ab_loop.dart';
import '../chapters/chapters_sheet.dart';
import '../sleep/sleep_timer_panel.dart';
import '../state/controls_visibility.dart';
import '../../widgets/failure_snack_bar.dart';
import '../tracks/track_sync_hud.dart';

/// Mini menu behind the top bar's "Más opciones" button. The A-B loop entry
/// joins this menu in 3c.
Future<void> showMoreMenu(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    // The menu has outgrown a fixed sheet: five rows do not fit a landscape
    // player, which is the orientation it is used in. Scroll-controlled and
    // bounded so adding a sixth is a non-event instead of an overflow.
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Consumer(
              builder: (_, sheetRef, __) {
                final engine = sheetRef.read(playbackEngineProvider);
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
                        showSleepTimerPanel(
                          context,
                          ref,
                          onBack: () => showMoreMenu(context, ref),
                        );
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
                    const SizedBox(height: 8),
                    // Always listed. Whether this video has chapters is only known
                    // after they are read, and reading them just to decide whether
                    // to show a row would defeat the deferred read entirely — so
                    // the sheet answers instead.
                    _MenuRow(
                      icon: Icons.format_list_numbered_rounded,
                      title: 'Capítulos',
                      subtitle: 'Saltar a una parte del video',
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        showChaptersSheet(context);
                      },
                    ),
                    const SizedBox(height: 8),
                    _MenuRow(
                      icon: Icons.photo_camera_outlined,
                      title: 'Capturar fotograma',
                      subtitle: 'Guardar esta imagen en la galería',
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _captureFrame(context, ref);
                      },
                    ),
                    const SizedBox(height: 8),
                    // Always enabled now that audio delay exists: even with subs
                    // off there is something to adjust. The capsule opens on
                    // whichever side is actually usable, and its own Sub|Audio
                    // switch moves between them.
                    StreamBuilder<MediaTrack?>(
                      stream: engine.currentSubtitleTrackStream,
                      initialData: engine.currentSubtitleTrack,
                      builder: (_, snap) {
                        final subsActive = snap.data != null;
                        return _MenuRow(
                          icon: Icons.compare_arrows_rounded,
                          title: 'Sincronizar audio y subtítulos',
                          subtitle: 'Ajustar el desfase mientras se reproduce',
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            ref
                                .read(syncHudProvider.notifier)
                                .show(
                                  subsActive
                                      ? SyncTarget.subtitles
                                      : SyncTarget.audio,
                                );
                          },
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

/// Captures the current frame and reports the outcome.
///
/// The messenger is captured before the await: the sheet this was tapped in is
/// already gone by the time the capture finishes.
Future<void> _captureFrame(BuildContext context, WidgetRef ref) async {
  // Captured before the await: the sheet this was tapped in is gone by the
  // time the capture finishes.
  final messenger = ScaffoldMessenger.of(context);
  _reportCapture(
    messenger,
    ref,
    await ref.read(frameCaptureProvider).capture(),
  );
}

/// Synchronous on purpose: everything it touches was captured before the
/// await, so no BuildContext crosses an async gap here.
void _reportCapture(
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  FrameCapture capture,
) {
  if (!capture.ok) {
    showFailureSnackBarOn(messenger, messenger.context, KivoOp.frameCapture);
    return;
  }

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          // The bytes are already in hand, so the thumbnail costs nothing and
          // proves at a glance that the right frame was caught.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.memory(
              capture.bytes!,
              width: 56,
              height: 32,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Captura guardada')),
        ],
      ),
      action: SnackBarAction(
        label: 'Ver',
        onPressed: () => ref.read(frameCaptureProvider).view(capture.uri!),
      ),
    ),
  );
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

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
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.42),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.42),
            ),
          ],
        ),
      ),
    );
  }
}
