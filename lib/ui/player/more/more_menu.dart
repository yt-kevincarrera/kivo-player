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
import '../../../player/chapters/chapters_provider.dart';
import '../../../player/loop/ab_loop.dart';
import '../../../player/open/video_source.dart';
import '../../../player/queue/queue_order.dart';
import '../../../player/sleep/sleep_timer.dart';
import '../bookmarks/bookmarks_sheet.dart';
import '../chapters/chapters_sheet.dart';
import '../sleep/sleep_timer_panel.dart';
import '../state/controls_visibility.dart';
import '../../settings/sections/equalizer_section.dart';
import '../../widgets/failure_snack_bar.dart';
import '../../widgets/press_bounce.dart';
import '../tracks/track_sync_hud.dart';

/// Mini menu behind the top bar's "Más opciones" button.
///
/// Regrouped from a flat list of rows into: a row of four one-shot action
/// tiles (mark here, capture, sleep timer, sync) followed by three captioned
/// groups — Reproducción (repeat/shuffle/A-B loop), Ir a (chapters/bookmarks)
/// and Audio (equalizer) — after users found the old ten-row list too long
/// and its dividers wrongly grouped (loop/repeat/shuffle split from each
/// other, bookmarking split from the bookmarks list).
///
/// In landscape the single column doesn't have the height to spare — the
/// player is normally used landscape, where the sheet's own viewport is
/// short — so past the width>height breakpoint the same groups lay out as
/// two columns instead: tiles + Reproducción on the left, Ir a + Audio on
/// the right, 12 px apart. Same widgets either way, just placed differently
/// (see `tilesRow`/`reproduccionGroup`/`iraGroup`/`audioGroup` below), so
/// there is exactly one place that builds each group's content.
Future<void> showMoreMenu(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    // Scroll-controlled and bounded so adding a row is a non-event instead
    // of an overflow — it overflowed twice before this.
    isScrollControlled: true,
    builder: (sheetContext) {
      // width > height (rather than a tablet-style `>= 600` breakpoint)
      // because this sheet only ever renders on a phone — the thing that
      // actually starves it for height is the player's own landscape use,
      // not the device class, so orientation is the more honest signal.
      final screenSize = MediaQuery.of(sheetContext).size;
      final isWide = screenSize.width > screenSize.height;
      // The two-column layout has room to spare width-wise but is still
      // tight on height at small landscape sizes, so it alone gets the
      // taller 0.92 cap (0.9 left the two columns 2 px short at 640×360) —
      // portrait keeps 0.8 exactly as before.
      final maxHeight = screenSize.height * (isWide ? 0.92 : 0.8);

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
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
                  final repeatIcon = repeatMode == RepeatMode.video
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded;
                  final repeatIconColor = repeatMode == RepeatMode.off
                      ? Colors.white70
                      : accent;
                  final chapters = sheetRef.watch(chaptersProvider);
                  final chaptersSubtitle = switch (chapters.length) {
                    0 => 'Sin capítulos',
                    1 => '1 capítulo',
                    final n => '$n capítulos',
                  };
                  final sleepState = sheetRef.watch(sleepTimerProvider);
                  final sleepBadge = switch (sleepState?.mode) {
                    null => null,
                    SleepTimerMode.fixed => fmtDuration(sleepState!.remaining),
                    SleepTimerMode.episode => 'Al terminar',
                    SleepTimerMode.episodes => '${sleepState!.episodesLeft} ep',
                  };

                  // Built once each, then placed either in a single column
                  // (portrait) or split across two (landscape) — see isWide
                  // above. Neither layout duplicates a widget tree.
                  final tilesRow = Row(
                    // Four one-shot actions: no state to show (Temporizador
                    // is the one exception — it carries its own active badge
                    // so an armed timer never goes invisible), no chevrons.
                    children: [
                      Expanded(
                        child: _MenuTile(
                          icon: Icons.bookmark_add_outlined,
                          label: 'Marcar aquí',
                          accent: accent,
                          onTap: () {
                            // Popped first, then acted on — same rule as
                            // frame capture below.
                            Navigator.of(sheetContext).pop();
                            _addBookmarkHere(context, ref);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MenuTile(
                          icon: Icons.photo_camera_outlined,
                          label: 'Capturar',
                          accent: accent,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _captureFrame(context, ref);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MenuTile(
                          icon: Icons.bedtime_outlined,
                          label: 'Temporizador',
                          accent: accent,
                          active: sleepState != null,
                          badge: sleepBadge,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            showSleepTimerPanel(
                              context,
                              ref,
                              onBack: () => showMoreMenu(context, ref),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        // Always enabled now that audio delay exists: even
                        // with subs off there is something to adjust. The
                        // capsule opens on whichever side is actually
                        // usable, and its own Sub|Audio switch moves
                        // between them.
                        child: StreamBuilder<MediaTrack?>(
                          stream: engine.currentSubtitleTrackStream,
                          initialData: engine.currentSubtitleTrack,
                          builder: (_, snap) {
                            final subsActive = snap.data != null;
                            return _MenuTile(
                              icon: Icons.compare_arrows_rounded,
                              label: 'Sincronizar',
                              accent: accent,
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
                      ),
                    ],
                  );

                  final reproduccionGroup = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _GroupCaption('Reproducción'),
                      _GroupCard(
                        children: [
                          _MenuRow(
                            icon: repeatIcon,
                            iconColor: repeatIconColor,
                            title: 'Repetir',
                            trailing: _SegmentedPill<RepeatMode>(
                              options: const [
                                (RepeatMode.off, 'No'),
                                (RepeatMode.list, 'Lista'),
                                (RepeatMode.video, 'Video'),
                              ],
                              selected: repeatMode,
                              accent: accent,
                              onChanged: (next) => ref
                                  .read(settingsProvider.notifier)
                                  .set(
                                    settings.copyWith(repeatMode: next.name),
                                  ),
                            ),
                          ),
                          // Stays visible and toggleable even with a
                          // single-video queue — hiding/showing it depending
                          // on the list would confuse more than an inert
                          // toggle does.
                          _MenuRow(
                            icon: Icons.shuffle_rounded,
                            iconColor: settings.shuffle
                                ? accent
                                : Colors.white70,
                            title: 'Aleatorio',
                            trailing: _SegmentedPill<bool>(
                              options: const [(false, 'No'), (true, 'Sí')],
                              selected: settings.shuffle,
                              accent: accent,
                              onChanged: (next) => ref
                                  .read(currentVideoProvider.notifier)
                                  .setShuffle(next),
                            ),
                          ),
                          _MenuRow(
                            icon: Icons
                                .linear_scale_rounded, // two points on a line: a range, not a repeat
                            title: 'Bucle A-B',
                            subtitle: loopSubtitle,
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              if (loop == null) {
                                ref.read(abLoopProvider.notifier).begin();
                                // Chip lives in the controls overlay — make
                                // sure it's visible.
                                ref
                                    .read(controlsVisibleProvider.notifier)
                                    .show();
                              } else {
                                ref.read(abLoopProvider.notifier).cancel();
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  );

                  final iraGroup = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _GroupCaption('Ir a'),
                      _GroupCard(
                        children: [
                          // Always listed. Whether this video has chapters
                          // is only known after they are read, and reading
                          // them just to decide whether to show a row would
                          // defeat the deferred read entirely — the count
                          // answers instead.
                          _MenuRow(
                            icon: Icons.format_list_numbered_rounded,
                            title: 'Capítulos',
                            subtitle: chaptersSubtitle,
                            onTap: () {
                              // Opens ON TOP of the menu: back returns here
                              // instead of to the video. Only the one-tap
                              // tiles close the menu.
                              showChaptersSheet(context);
                            },
                          ),
                          // Always listed, same reasoning as Capítulos
                          // above: count is only known from the store, and
                          // this row is what shows it.
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
                              showBookmarksSheet(context);
                            },
                          ),
                        ],
                      ),
                    ],
                  );

                  final audioGroup = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _GroupCaption('Audio'),
                      _GroupCard(
                        children: [
                          _MenuRow(
                            icon: Icons.equalizer_rounded,
                            iconColor: eq.enabled ? accent : Colors.white70,
                            title: 'Ecualizador',
                            subtitle: presetNameFor(eq),
                            onTap: () {
                              Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(
                                  builder: (_) => const EqualizerSection(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  );

                  final body = isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  tilesRow,
                                  const SizedBox(height: 14),
                                  reproduccionGroup,
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  iraGroup,
                                  const SizedBox(height: 14),
                                  audioGroup,
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            tilesRow,
                            const SizedBox(height: 14),
                            reproduccionGroup,
                            const SizedBox(height: 14),
                            iraGroup,
                            const SizedBox(height: 14),
                            audioGroup,
                          ],
                        );

                  return Column(
                    // Keyed so a widget test can measure this column's
                    // actual rendered height against the sheet's height cap.
                    key: const Key('more-menu-content'),
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
                      body,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
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

/// A small caption above a [_GroupCard] — replaces the old hairline dividers
/// so each group of the menu reads as a named cluster instead of an
/// unlabeled run of rows.
class _GroupCaption extends StatelessWidget {
  final String label;
  const _GroupCaption(this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
    child: Text(
      label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.4),
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
  );
}

/// One dark card (the same `0xFF182036` surface every row used individually
/// before) holding several flat [_MenuRow]s, hairline-separated.
class _GroupCard extends StatelessWidget {
  final List<Widget> children;
  const _GroupCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF182036),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1)
            Divider(
              height: 1,
              thickness: 1,
              indent: 54,
              endIndent: 12,
              color: Colors.white.withValues(alpha: 0.06),
            ),
        ],
      ],
    ),
  );
}

/// One of the four equal action tiles at the top of the menu: icon, label,
/// and an optional accent badge (used only by Temporizador, to keep an
/// active timer from going invisible in a row of otherwise stateless
/// tiles). The whole tile is the tap target.
class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  final String? badge;
  final bool active;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.badge,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = active ? accent : Colors.white70;
    return PressBounce(
      onTap: onTap,
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF182036),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 27, color: iconColor),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(height: 1),
              Text(
                badge!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Overrides the default chevron. Used by rows (Repetir, Aleatorio) whose
  /// state is changed directly on the row rather than by navigating away —
  /// those pass an inline control here and leave [onTap] null, since the
  /// control's own segments already handle the tap.
  final Widget? trailing;

  const _MenuRow({
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
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
          // maxLines+ellipsis on both lines: a wide trailing control (the
          // two-column layout's Repetir pill, mainly) can squeeze this down
          // to a sliver — without a line cap, that's not a shorter row, it's
          // "Repetir" wrapping one letter per line and the row growing to
          // match. Ellipsis keeps the row's height fixed no matter how
          // little width it's given.
          child: subtitle == null
              ? Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(width: 8),
        trailing ??
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.42),
            ),
      ],
    );

    final padding = EdgeInsets.symmetric(
      horizontal: 12,
      vertical: subtitle == null ? 10 : 12,
    );

    if (onTap == null) {
      return Padding(padding: padding, child: content);
    }
    return InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: content),
    );
  }
}

/// A pill of 2-3 mutually exclusive segments, in the same look as the
/// Sub|Audio switch inside the track-sync HUD (`_TargetToggle`/`_TargetChip`
/// in track_sync_hud.dart): a translucent capsule holding chips that fill
/// solid-accent when selected. Reused here for Repetir (3 segments) and
/// Aleatorio (2 segments) so both inline controls speak the same visual
/// language as the rest of the player's controls.
class _SegmentedPill<T> extends StatelessWidget {
  final List<(T value, String label)> options;
  final T selected;
  final Color accent;
  final ValueChanged<T> onChanged;

  const _SegmentedPill({
    required this.options,
    required this.selected,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            _SegmentChip(
              label: o.$2,
              active: o.$1 == selected,
              accent: accent,
              onTap: () => onChanged(o.$1),
            ),
        ],
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _SegmentChip({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? onAccent(accent)
                : Colors.white.withValues(alpha: 0.55),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
