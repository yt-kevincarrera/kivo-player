// Flutter's animation package also has a RepeatMode; the queue's is meant.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/media_file_ops_provider.dart';
import '../../../player/end_actions/end_flow.dart';
import '../../../player/end_actions/trash_queue.dart';
import '../../../player/library/media_index.dart';
import '../../../player/open/video_source.dart';
import '../../../player/queue/queue_order.dart';

String afterEndLabel(AppLocalizations l10n, AfterEnd a) => switch (a) {
  AfterEnd.keepGoing => l10n.endActionsAfterKeepGoing,
  AfterEnd.restart => l10n.endActionsRestart,
  AfterEnd.closePlayer => l10n.endActionsAfterClosePlayer,
  AfterEnd.closeApp => l10n.endActionsAfterCloseApp,
  AfterEnd.screenOff => l10n.endActionsAfterScreenOff,
};

IconData afterEndIcon(AfterEnd a) => switch (a) {
  AfterEnd.keepGoing => Icons.playlist_play_rounded,
  AfterEnd.restart => Icons.replay_rounded,
  AfterEnd.closePlayer => Icons.close_fullscreen_rounded,
  AfterEnd.closeApp => Icons.power_settings_new_rounded,
  AfterEnd.screenOff => Icons.brightness_low_rounded,
};

/// «Papelera · Cerrar Kivo», «Papelera», «Cerrar Kivo» or «Nada» — the menu
/// row's subtitle and the chip's text.
String endActionsSummary(
  AppLocalizations l10n,
  EndActions a, {
  required bool toTrash,
}) {
  final trash = toTrash
      ? l10n.endActionsSummaryTrash
      : l10n.endActionsSummaryDelete;
  final hasAfter = a.after != AfterEnd.keepGoing;
  if (a.after == AfterEnd.restart) return afterEndLabel(l10n, a.after);
  if (a.trash && hasAfter) {
    return l10n.endActionsSummaryBoth(trash, afterEndLabel(l10n, a.after));
  }
  if (a.trash) return trash;
  if (hasAfter) return afterEndLabel(l10n, a.after);
  return l10n.endActionsSummaryNone;
}

/// [onBack] reopens the «Más» menu, as the sleep timer panel does.
Future<void> showEndActionsPanel(
  BuildContext context, {
  VoidCallback? onBack,
  bool globalSettings = false,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: KivoColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (_) =>
        EndActionsPanel(onBack: onBack, globalSettings: globalSettings),
  );
}

class EndActionsPanel extends ConsumerWidget {
  final VoidCallback? onBack;
  final bool globalSettings;
  const EndActionsPanel({super.key, this.onBack, this.globalSettings = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final settings = ref.watch(settingsProvider);
    final currentActions = ref.watch(endActionsProvider);
    final actions = globalSettings
        ? EndActions.saved(settings)
        : currentActions;
    final notifier = ref.read(endActionsProvider.notifier);
    final toTrash = ref.watch(mediaFileOpsProvider).movesToTrash;
    final session = ref.watch(currentVideoProvider);
    final inLibrary =
        session != null &&
        libraryItemIn(ref.watch(mediaIndexProvider).valueOrNull, session) !=
            null;
    final repeatVideo =
        repeatModeFor(ref.watch(settingsProvider).repeatMode) ==
        RepeatMode.video;
    final trashBlockedReason = actions.after == AfterEnd.restart
        ? l10n.endActionsTrashRestart
        : !globalSettings && !inLibrary
        ? l10n.endActionsTrashNotLibrary
        : !globalSettings && repeatVideo
        ? l10n.endActionsTrashRepeatVideo
        : null;
    final trashUsable = trashBlockedReason == null;

    void close() => Navigator.of(context).pop();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
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
              Row(
                children: [
                  if (onBack != null) ...[
                    _SquareButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () {
                        close();
                        onBack!();
                      },
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      l10n.endActionsTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _SquareButton(
                    icon: Icons.close_rounded,
                    label: MaterialLocalizations.of(context).closeButtonTooltip,
                    onTap: close,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Card(
                children: [
                  _Row(
                    icon: Icons.public_rounded,
                    iconColor: settings.endActionsGlobal
                        ? accent
                        : Colors.white70,
                    title: l10n.endActionsGlobal,
                    subtitle: settings.endActionsGlobal
                        ? l10n.endActionsGlobalHint
                        : globalSettings
                        ? l10n.endActionsSavedHint
                        : l10n.endActionsSessionHint,
                    trailing: Switch(
                      key: const Key('end-global-switch'),
                      value: settings.endActionsGlobal,
                      activeThumbColor: accent,
                      onChanged: (on) =>
                          notifier.setGlobal(on, useCurrent: !globalSettings),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Card(
                children: [
                  _Row(
                    key: const Key('end-trash-row'),
                    icon: Icons.delete_outline_rounded,
                    iconColor: actions.trash && trashUsable
                        ? accent
                        : Colors.white70,
                    title: toTrash
                        ? l10n.endActionsTrashTitle
                        : l10n.endActionsDeleteTitle,
                    subtitle:
                        trashBlockedReason ?? l10n.endActionsTrashSubtitle,
                    enabled: trashUsable,
                    trailing: Switch(
                      key: const Key('end-trash-switch'),
                      value: actions.trash && trashUsable,
                      activeThumbColor: accent,
                      onChanged: trashUsable
                          ? (globalSettings
                                ? notifier.setSavedTrash
                                : notifier.setTrash)
                          : null,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Text(
                  l10n.endActionsAfterTitle.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              _Card(
                children: [
                  for (final a in AfterEnd.values)
                    _Row(
                      key: Key('end-after-${a.name}'),
                      icon: afterEndIcon(a),
                      iconColor: actions.after == a ? accent : Colors.white70,
                      title: afterEndLabel(l10n, a),
                      subtitle: a == AfterEnd.screenOff
                          ? l10n.endActionsAfterScreenOffHint
                          : a == AfterEnd.restart
                          ? l10n.endActionsRestartHint
                          : null,
                      selected: actions.after == a,
                      accent: accent,
                      onTap: () => globalSettings
                          ? notifier.setSavedAfter(a)
                          : notifier.setAfter(a),
                      trailing: actions.after == a
                          ? Icon(Icons.check_rounded, color: accent, size: 20)
                          : null,
                    ),
                ],
              ),
              if (!globalSettings) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (!actions.trash && trashUsable) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('end-trash-and-next'),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(
                            Icons.delete_sweep_outlined,
                            size: 18,
                          ),
                          onPressed: () {
                            close();
                            ref.read(trashAndNextProvider.notifier).state++;
                          },
                          label: Text(
                            toTrash
                                ? l10n.endActionsTrashAndNext
                                : l10n.endActionsDeleteAndNext,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: ElevatedButton.icon(
                        key: const Key('end-finish-now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: onAccent(accent),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.skip_next_rounded, size: 18),
                        onPressed: actions.isActive
                            ? () {
                                close();
                                ref.read(finishNowProvider.notifier).state++;
                              }
                            : null,
                        label: Text(l10n.endActionsFinishNow),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  const _SquareButton({required this.icon, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label ?? MaterialLocalizations.of(context).backButtonTooltip,
    onPressed: onTap,
    icon: Icon(icon, size: 22, color: Colors.white70),
  );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(14),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool selected;
  final Color? accent;
  const _Row({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.selected = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: selected && accent != null
                              ? accent
                              : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
