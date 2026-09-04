import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/kivo_failure.dart';
import '../../core/settings/settings_provider.dart';
import '../../core/update/release_notes.dart';
import '../../core/update/update_download_controller.dart';
import '../../core/update/update_info.dart';
import '../../core/update/update_providers.dart';
import '../../l10n/l10n.dart';
import '../../platform/interfaces/app_installer.dart';

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) =>
    showDialog<void>(context: context, builder: (_) => _UpdateDialog(info));

/// Re-opens the dialog on a download that is already queued or finished,
/// without an [UpdateInfo] and therefore without touching the network. This is
/// how a hidden download gets its Instalar button back while offline.
Future<void> showPendingUpdateDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _UpdateDialog(null));

class _UpdateDialog extends ConsumerStatefulWidget {
  const _UpdateDialog(this.info);

  /// Null when opened from an in-flight download rather than from a check.
  final UpdateInfo? info;

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  /// Held from initState so dispose never has to touch ref.
  late final UpdateDownloadNotifier _dl;

  @override
  void initState() {
    super.initState();
    _dl = ref.read(updateDownloadProvider.notifier);
    _dl.startWatching();
  }

  @override
  void dispose() {
    _dl.stopWatching();
    super.dispose();
  }

  UpdateInfo? get _info => widget.info;

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(updateDownloadProvider);
    final accent = Color(ref.watch(settingsProvider.select((s) => s.accentColor)));
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final version = _info?.version ?? st.version;

    return AlertDialog(
      title: Text(version == null ? l10n.updateGenericTitle : l10n.updateTitleWithVersion(version)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(child: _content(context, st, accent, cs)),
      ),
      actions: _actions(context, st),
    );
  }

  Widget _content(BuildContext context, UpdateDownloadState st, Color accent, ColorScheme cs) {
    final l10n = context.l10n;
    final muted = TextStyle(color: cs.onSurfaceVariant, fontSize: 13);
    switch (st.phase) {
      case DownloadPhase.idle:
        final info = _info;
        if (info == null) {
          return Text(l10n.updateNoActiveDownload, style: muted);
        }
        // Stripped of headings and the compare link: a URL is no use inside a
        // dialog, and older releases contain nothing else.
        final notes = cleanReleaseNotes(info.notes);
        return Text(
          notes.isEmpty ? l10n.updateNoNotesAvailable : notes,
          style: muted,
        );
      case DownloadPhase.downloading:
        return _progressBlock(
          st.progress,
          accent,
          cs,
          caption: _statusLine(context, st.progress),
          hint: l10n.updateCanLeaveHint,
        );
      case DownloadPhase.ready:
        return _progressBlock(
          const DownloadProgress(DownloadStage.done, received: 1, total: 1),
          accent,
          cs,
          caption: l10n.updateReadyCaption,
          hint: l10n.updateReadyHint,
        );
      case DownloadPhase.failed:
        final f = kivoErrorCatalog[KivoOp.updateInstall]!;
        return Text(
          l10n.updateFailedMessage(f.message, f.code),
          style: muted,
        );
    }
  }

  Widget _progressBlock(
    DownloadProgress p,
    Color accent,
    ColorScheme cs, {
    required String caption,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SegmentedBar(fraction: p.fraction, accent: accent, cs: cs, dimmed: p.isPaused),
        const SizedBox(height: 10),
        Text(
          caption,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        Text(hint, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
      ],
    );
  }

  List<Widget> _actions(BuildContext context, UpdateDownloadState st) {
    final l10n = context.l10n;
    final info = _info;
    switch (st.phase) {
      case DownloadPhase.idle:
        if (info == null) return [_closeButton(context)];
        return [
          TextButton(
            onPressed: () {
              ref.read(updateControllerProvider).skip(info.version);
              Navigator.pop(context);
            },
            child: Text(l10n.updateSkipVersionAction),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonNotNow),
          ),
          FilledButton(
            onPressed: info.apkUrl == null
                ? () {
                    ref.read(updateControllerProvider).openInBrowser(info);
                    Navigator.pop(context);
                  }
                : () => _dl.start(info),
            child: Text(info.apkUrl == null ? l10n.updateOpenInBrowserAction : l10n.updateDownloadAction),
          ),
        ];
      case DownloadPhase.downloading:
        return [
          TextButton(onPressed: _dl.cancel, child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.updateHideAction),
          ),
          // Present but inert, so it is obvious where the install will happen.
          FilledButton(onPressed: null, child: Text(l10n.updateInstallAction)),
        ];
      case DownloadPhase.ready:
        return [
          // Without a way out, a downloaded APK you no longer want is
          // permanent: it keeps its 30 MB and keeps claiming the update slot,
          // which is how an updater bug once made itself unfixable in-app.
          TextButton(onPressed: _dl.cancel, child: Text(l10n.updateDiscardReadyAction)),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonNotNow),
          ),
          FilledButton(
            onPressed: () => _install(_dl.install()),
            child: Text(l10n.updateInstallAction),
          ),
        ];
      case DownloadPhase.failed:
        return [
          if (info == null)
            _closeButton(context)
          else
            TextButton(
              onPressed: () {
                ref.read(updateControllerProvider).openInBrowser(info);
                Navigator.pop(context);
              },
              child: Text(l10n.updateOpenInBrowserAction),
            ),
          FilledButton(
            onPressed: () => _install(_dl.retry(info)),
            child: Text(l10n.updateRetryAction),
          ),
        ];
    }
  }

  Widget _closeButton(BuildContext context) => TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.commonClose),
      );

  /// Reports the outcome of an install attempt. A null outcome means a fresh
  /// download was queued instead, which the progress block already narrates.
  Future<void> _install(Future<InstallOutcome?> pending) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final outcome = await pending;
    if (!mounted || outcome == null) return;
    switch (outcome) {
      case InstallOutcome.started:
        Navigator.pop(context);
      case InstallOutcome.needsPermission:
        messenger.showSnackBar(SnackBar(
          content: Text(l10n.updateInstallNeedsPermissionSnackbar),
        ));
      case InstallOutcome.failed:
        break; // the dialog already switched to its failed state
    }
  }
}

String _statusLine(BuildContext context, DownloadProgress p) {
  final l10n = context.l10n;
  final size = p.total > 0
      ? '${_mb(p.received)} / ${_mb(p.total)} MB'
      : '${_mb(p.received)} MB';
  final pct = p.fraction;
  return switch (p.stage) {
    DownloadStage.pending => l10n.updateStatusQueued,
    DownloadStage.pausedNetwork => l10n.updateStatusPausedNetwork,
    DownloadStage.pausedRetry => l10n.updateStatusPausedRetry,
    _ => pct == null ? size : l10n.updateStatusSizePercent(size, (pct * 100).round()),
  };
}

String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1).replaceAll('.', ',');

/// Kivo's signature meter: discrete segments, lit in the accent colour.
class _SegmentedBar extends StatelessWidget {
  const _SegmentedBar({
    required this.fraction,
    required this.accent,
    required this.cs,
    this.dimmed = false,
  });

  final double? fraction;
  final Color accent;
  final ColorScheme cs;

  /// Paused: the lit segments stay put but lose their glow.
  final bool dimmed;

  static const _segments = 24;

  @override
  Widget build(BuildContext context) {
    final lit = ((fraction ?? 0) * _segments).round();
    final on = dimmed ? accent.withValues(alpha: 0.45) : accent;
    final off = cs.onSurface.withValues(alpha: 0.18);
    return Row(
      children: [
        for (var i = 0; i < _segments; i++)
          Expanded(
            child: Container(
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 0.5),
              color: i < lit ? on : off,
            ),
          ),
      ],
    );
  }
}
