import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/kivo_failure.dart';
import '../../core/settings/settings_provider.dart';
import '../../core/update/release_notes.dart';
import '../../core/update/update_download_controller.dart';
import '../../core/update/update_info.dart';
import '../../core/update/update_providers.dart';
import '../../l10n/l10n.dart';
import '../../platform/app_installer_provider.dart';
import '../../platform/interfaces/app_installer.dart';

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) =>
    showDialog<void>(context: context, builder: (_) => _UpdateDialog(info));

/// Re-opens the dialog on a download that is already queued or finished,
/// without an [UpdateInfo] and therefore without touching the network. This is
/// how a hidden download gets its Instalar button back while offline.
Future<void> showPendingUpdateDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _UpdateDialog(null),
);

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
  UpdatePreview? _preview;
  bool _checkingSize = false;
  int _previewGeneration = 0;

  @override
  void initState() {
    super.initState();
    _dl = ref.read(updateDownloadProvider.notifier);
    _dl.startWatching();
    _requestPreview();
  }

  @override
  void dispose() {
    _previewGeneration++;
    _dl.stopWatching();
    super.dispose();
  }

  UpdateInfo? get _info => widget.info;

  void _requestPreview() {
    final info = _info;
    if (info?.apkUrl == null ||
        ref.read(updateDownloadProvider).phase != DownloadPhase.idle) {
      return;
    }
    _checkingSize = true;
    final generation = ++_previewGeneration;
    unawaited(_resolvePreview(info!, generation));
  }

  Future<void> _resolvePreview(UpdateInfo info, int generation) async {
    UpdatePreview? preview;
    try {
      preview = await ref
          .read(appInstallerProvider)
          .previewUpdate(info.apkUrl!, manifestUrl: info.manifestUrl);
    } catch (_) {
      // Size discovery is optional; a release asset size is an upper bound.
    }
    if (!mounted || generation != _previewGeneration) return;
    setState(() {
      _preview = preview;
      _checkingSize = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UpdateDownloadState>(updateDownloadProvider, (previous, next) {
      if (previous?.phase == next.phase) return;
      if (next.phase == DownloadPhase.idle) {
        _requestPreview();
      } else {
        // A resumed/native download can become visible while discovery is in
        // flight. Its late result must not change the active download's UI.
        _previewGeneration++;
        _checkingSize = false;
      }
    });
    final st = ref.watch(updateDownloadProvider);
    final accent = Color(
      ref.watch(settingsProvider.select((s) => s.accentColor)),
    );
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final version = _info?.version ?? st.version;

    return AlertDialog(
      scrollable: true,
      title: Text(
        version == null
            ? l10n.updateGenericTitle
            : l10n.updateTitleWithVersion(version),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _content(context, st, accent, cs),
      ),
      actions: _actions(context, st),
    );
  }

  Widget _content(
    BuildContext context,
    UpdateDownloadState st,
    Color accent,
    ColorScheme cs,
  ) {
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (info.apkUrl != null) ...[
              _sizePreview(context, info, cs),
              const SizedBox(height: 16),
            ],
            Text(
              notes.isEmpty ? l10n.updateNoNotesAvailable : notes,
              style: muted,
            ),
          ],
        );
      case DownloadPhase.downloading:
        return _progressBlock(
          st.progress,
          accent,
          cs,
          caption: _statusLine(context, st.progress),
          hint: st.progress.stage == DownloadStage.preparing
              ? l10n.updatePreparingHint
              : st.progress.partial
              ? l10n.updatePartialDownloadHint
              : st.progress.fallback
              ? l10n.updateFullDownloadFallbackHint
              : l10n.updateCanLeaveHint,
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
        return Text(l10n.updateFailedMessage(f.message, f.code), style: muted);
    }
  }

  Widget _sizePreview(BuildContext context, UpdateInfo info, ColorScheme cs) {
    final l10n = context.l10n;
    final bytes = _positiveSize(_preview?.bytes);
    final fullBytes = _positiveSize(_preview?.fullBytes);
    final upperBound = fullBytes ?? _positiveSize(info.apkSizeBytes);
    final partial = _preview?.partial == true && bytes != null;
    final label = _checkingSize
        ? l10n.updateSizeChecking
        : bytes != null
        ? (partial
              ? l10n.updatePartialDownloadSize(_formatBytes(context, bytes))
              : l10n.updateFullDownloadSize(_formatBytes(context, bytes)))
        : upperBound != null
        ? l10n.updateDownloadSizeUpperBound(_formatBytes(context, upperBound))
        : l10n.updateSizeUnavailable;
    return Semantics(
      liveRegion: true,
      child: Column(
        key: const Key('update-size-preview'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!_checkingSize && partial && fullBytes != null) ...[
            const SizedBox(height: 4),
            Text(
              l10n.updateFullDownloadAlternative(
                _formatBytes(context, fullBytes),
              ),
              style: TextStyle(color: cs.onSurface, fontSize: 12),
            ),
          ],
        ],
      ),
    );
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
        if (p.stage == DownloadStage.preparing)
          LinearProgressIndicator(
            color: accent,
            backgroundColor: cs.onSurface.withValues(alpha: 0.18),
          )
        else
          _SegmentedBar(
            fraction: p.fraction,
            accent: accent,
            cs: cs,
            dimmed: p.isPaused,
          ),
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
                : _checkingSize
                ? null
                : () => _dl.start(info),
            child: Text(
              info.apkUrl == null
                  ? l10n.updateOpenInBrowserAction
                  : l10n.updateDownloadAction,
            ),
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
          TextButton(
            onPressed: _dl.cancel,
            child: Text(l10n.updateDiscardReadyAction),
          ),
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
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.updateInstallNeedsPermissionSnackbar)),
        );
      case InstallOutcome.failed:
        break; // the dialog already switched to its failed state
    }
  }
}

String _statusLine(BuildContext context, DownloadProgress p) {
  final l10n = context.l10n;
  final size = p.total > 0
      ? '${_mb(context, p.received)} / ${_mb(context, p.total)} MB'
      : '${_mb(context, p.received)} MB';
  final pct = p.fraction;
  return switch (p.stage) {
    DownloadStage.pending => l10n.updateStatusQueued,
    DownloadStage.preparing => l10n.updateStatusPreparing,
    DownloadStage.pausedNetwork => l10n.updateStatusPausedNetwork,
    DownloadStage.pausedRetry => l10n.updateStatusPausedRetry,
    _ =>
      pct == null
          ? size
          : l10n.updateStatusSizePercent(size, (pct * 100).round()),
  };
}

int? _positiveSize(int? bytes) => bytes != null && bytes > 0 ? bytes : null;

String _formatBytes(BuildContext context, int bytes) {
  final locale = Localizations.localeOf(context).toString();
  final format = NumberFormat('0.#', locale);
  if (bytes < 1000) return '${format.format(bytes)} B';
  if (bytes < 1000000) return '${format.format(bytes / 1000)} KB';
  return '${format.format(bytes / 1000000)} MB';
}

String _mb(BuildContext context, int bytes) => NumberFormat(
  '0.#',
  Localizations.localeOf(context).toString(),
).format(bytes / 1000000);

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
