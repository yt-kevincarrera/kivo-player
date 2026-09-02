// Flutter's own animation package also defines a `RepeatMode` — hide it so
// the queue's RepeatMode (repeat off/list/video) is the one in scope here.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/engine/playback_engine.dart';
import '../../../player/engine/playback_provider.dart';
import '../../../core/errors/kivo_failure.dart';
import '../../../player/audio/equalizer.dart';
import '../../../player/audio/equalizer_controller.dart';
import '../../../player/bookmarks/bookmark.dart';
import '../../../player/bookmarks/bookmarks_provider.dart';
import '../../../player/capture/frame_capture_controller.dart';
import '../../../player/loop/ab_loop.dart';
import '../../../player/open/video_source.dart';
import '../../../player/queue/queue_order.dart';
import '../bookmarks/bookmarks_sheet.dart';
import '../chapters/chapters_sheet.dart';
import '../sleep/sleep_timer_panel.dart';
import '../state/controls_visibility.dart';
import '../../settings/sections/equalizer_section.dart';
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
    // The menu has outgrown a fixed sheet: ten rows in four groups (playback
    // modes, marks, capture, audio) are about two and a half landscape
    // screens, which is the orientation the player is used in.
    // Scroll-controlled and bounded so adding a row is a non-event instead
    // of an overflow — it overflowed twice before this.
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
                final settings = sheetRef.watch(settingsProvider);
                final accent = Color(settings.accentColor);
                final eq = sheetRef.watch(equalizerProvider);
                final repeatMode = repeatModeFor(settings.repeatMode);
                final repeatSubtitle = switch (repeatMode) {
                  RepeatMode.off => 'Desactivado',
                  RepeatMode.list => 'Toda la lista',
                  RepeatMode.video => 'Este video',
                };
                final repeatIcon = repeatMode == RepeatMode.video
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded;
                final repeatIconColor = repeatMode == RepeatMode.off
                    ? Colors.white70
                    : accent;
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
                      icon: Icons
                          .linear_scale_rounded, // two points on a line: a range, not a repeat

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
                    _MenuRow(
                      icon: repeatIcon,
                      iconColor: repeatIconColor,
                      title: 'Repetir',
                      chevron: false,
                      subtitle: repeatSubtitle,
                      onTap: () {
                        final next = switch (repeatMode) {
                          RepeatMode.off => RepeatMode.list,
                          RepeatMode.list => RepeatMode.video,
                          RepeatMode.video => RepeatMode.off,
                        };
                        ref
                            .read(settingsProvider.notifier)
                            .set(settings.copyWith(repeatMode: next.name));
                      },
                    ),
                    const SizedBox(height: 8),
                    // Stays visible and toggleable even with a single-video
                    // queue — hiding/showing it depending on the list would
                    // confuse more than an inert toggle does.
                    _MenuRow(
                      icon: Icons.shuffle_rounded,
                      iconColor: settings.shuffle ? accent : Colors.white70,
                      title: 'Aleatorio',
                      chevron: false,
                      subtitle: settings.shuffle ? 'Activado' : 'Desactivado',
                      onTap: () {
                        ref
                            .read(currentVideoProvider.notifier)
                            .setShuffle(!settings.shuffle);
                      },
                    ),
                    const SizedBox(height: 8),
                    // Always listed. Whether this video has chapters is only known
                    // after they are read, and reading them just to decide whether
                    // to show a row would defeat the deferred read entirely — so
                    // the sheet answers instead.
                    const _MenuDivider(),
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
                      icon: Icons.bookmark_add_outlined,
                      title: 'Marcar aquí',
                      subtitle: 'Guardar este momento del video',
                      onTap: () {
                        // Popped first, then acted on — same rule as frame
                        // capture below.
                        Navigator.of(sheetContext).pop();
                        _addBookmarkHere(context, ref);
                      },
                    ),
                    const SizedBox(height: 8),
                    // Always listed, same reasoning as Capítulos above: count
                    // is only known from the store, and this row is what
                    // shows it.
                    _MenuRow(
                      icon: Icons.bookmark_outline_rounded,
                      title: 'Marcadores',
                      subtitle: switch (sheetRef
                          .watch(bookmarksProvider)
                          .length) {
                        0 => 'Sin marcadores',
                        1 => '1 marcador',
                        final n => '$n marcadores',
                      },
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        showBookmarksSheet(context);
                      },
                    ),
                    const SizedBox(height: 8),
                    const _MenuDivider(),
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
                    const _MenuDivider(),
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
                    const SizedBox(height: 8),
                    _MenuRow(
                      icon: Icons.equalizer_rounded,
                      iconColor: eq.enabled ? accent : Colors.white70,
                      title: 'Ecualizador',
                      subtitle: presetNameFor(eq),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (_) => const EqualizerSection(),
                          ),
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

/// Saves the current position as an unnamed bookmark and reports it with a
/// SnackBar offering to name it. Asking for a name up front is what makes
/// people never bookmark anything, so the save happens first, no dialog.
///
/// [context] here is the screen showMoreMenu was opened from, not the sheet's
/// own — the sheet was already popped by the caller before this runs — so it
/// stays mounted for as long as the player screen itself does, well past the
/// SnackBar's own lifetime. Messenger and position are captured before the
/// await regardless, same rule as [_captureFrame] below.
Future<void> _addBookmarkHere(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  // The video this mark belongs to, captured NOW: «Nombrar» fires from a
  // SnackBar that can outlive the video, and a rename must never land on
  // whatever opened next.
  final videoKey = ref.read(currentVideoProvider)?.resumeKey;
  final position = ref.read(positionProvider).value ?? Duration.zero;
  final bookmark = await ref
      .read(bookmarksProvider.notifier)
      .add(position.inMilliseconds, key: videoKey);

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text('Marcador guardado · ${fmtDuration(position)}'),
      action: SnackBarAction(
        label: 'Nombrar',
        onPressed: () => _nameBookmark(context, ref, bookmark, videoKey),
      ),
    ),
  );
}

/// Names a just-saved bookmark, from the SnackBar's "Nombrar" action.
///
/// Guarded by `context.mounted`: this fires from a user tap that can land
/// well after the SnackBar first showed, so the screen it belongs to may be
/// gone by then. Looked up again by identity ([bookmark] is unrenamed at
/// this point, so value equality still finds it) rather than trusting a
/// stored index: other bookmarks may have been added or removed meanwhile.
Future<void> _nameBookmark(
  BuildContext context,
  WidgetRef ref,
  Bookmark bookmark,
  String? videoKey,
) async {
  if (!context.mounted) return;
  final name = await promptBookmarkName(context);
  if (name == null) return;
  // Same video still? Otherwise the mark is not in this list and the
  // notifier would refuse the stale key anyway — bail before looking.
  if (ref.read(currentVideoProvider)?.resumeKey != videoKey) return;
  final index = ref.read(bookmarksProvider).indexOf(bookmark);
  if (index < 0) return;
  await ref.read(bookmarksProvider.notifier).rename(index, name, key: videoKey);
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

/// A hairline between the menu's groups (playback modes · marks · capture ·
/// audio). Ten rows with no seams read as one undifferentiated list.
class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: 20,
    endIndent: 20,
    color: Colors.white.withValues(alpha: 0.08),
  );
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// False for rows that toggle in place: a chevron promises navigation,
  /// and these go nowhere.
  final bool chevron;

  const _MenuRow({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.chevron = true,
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
              child: Icon(icon, size: 16, color: iconColor ?? Colors.white70),
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
            if (chevron)
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
