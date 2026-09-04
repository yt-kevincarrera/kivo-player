import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../l10n/l10n.dart';
import '../../../player/chapters/chapter.dart';
import '../../../player/chapters/chapters_provider.dart';
import '../../../player/control/player_controller.dart';
import '../../../player/engine/playback_provider.dart';

Future<void> showChaptersSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (_) => const _ChaptersSheet(),
  );
}

class _ChaptersSheet extends ConsumerWidget {
  const _ChaptersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapters = ref.watch(chaptersProvider);
    final current = ref.watch(currentChapterProvider);
    final accent = Color(ref.watch(settingsProvider).accentColor);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
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
            Text(
              context.l10n.playerChaptersTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 12),
            if (chapters.isNotEmpty) ...[
              // Free, because the list is already in memory: skipping is a
              // search through it, not another round trip to mpv.
              _SkipRow(accent: accent),
              const SizedBox(height: 12),
            ],
            if (chapters.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  context.l10n.playerChaptersEmpty,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
              )
            else
              // Bounded so a film with fifty chapters scrolls instead of
              // growing the sheet past the screen.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: chapters.length,
                  itemBuilder: (_, i) => _ChapterRow(
                    chapter: chapters[i],
                    number: i + 1,
                    active: chapters[i] == current,
                    accent: accent,
                    onTap: () {
                      Navigator.of(context).pop();
                      ref
                          .read(playerControllerProvider)
                          .seekTo(chapters[i].start);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Previous / next chapter, without leaving the sheet.
///
/// Both are disabled at the ends rather than hidden: a control that appears
/// and vanishes as you move through a film is harder to aim at than one that
/// simply greys out.
class _SkipRow extends ConsumerWidget {
  const _SkipRow({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapters = ref.watch(chaptersProvider);
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final back = previousChapterStart(chapters, position);
    final forward = nextChapterStart(chapters, position);

    void go(Duration? target) {
      if (target == null) return;
      ref.read(playerControllerProvider).seekTo(target);
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _SkipButton(
          key: const ValueKey('chapter-previous'),
          icon: Icons.skip_previous_rounded,
          label: context.l10n.playerChaptersPrevious,
          enabled: back != null,
          accent: accent,
          onTap: () => go(back),
        ),
        _SkipButton(
          key: const ValueKey('chapter-next'),
          icon: Icons.skip_next_rounded,
          label: context.l10n.playerChaptersNext,
          enabled: forward != null,
          accent: accent,
          onTap: () => go(forward),
        ),
      ],
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF182036),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({
    required this.chapter,
    required this.number,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final MediaChapter chapter;
  final int number;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: active
                ? accent.withValues(alpha: 0.16)
                : const Color(0xFF182036),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: active
                  ? accent.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  '$number',
                  style: TextStyle(
                    color: active
                        ? accent
                        : Colors.white.withValues(alpha: 0.42),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  chapter.title.isEmpty
                      ? context.l10n.chapterFallback(number)
                      : chapter.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? accent : Colors.white,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                fmtDuration(chapter.start),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.42),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
