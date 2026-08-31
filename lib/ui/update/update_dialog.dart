import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/kivo_failure.dart';
import '../../core/settings/settings_provider.dart';
import '../../core/update/release_notes.dart';
import '../../core/update/update_download_controller.dart';
import '../../core/update/update_info.dart';
import '../../core/update/update_providers.dart';
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
    final version = _info?.version ?? st.version;

    return AlertDialog(
      title: Text(version == null ? 'Actualización' : 'Nueva versión $version'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(child: _content(st, accent, cs)),
      ),
      actions: _actions(st),
    );
  }

  Widget _content(UpdateDownloadState st, Color accent, ColorScheme cs) {
    final muted = TextStyle(color: cs.onSurfaceVariant, fontSize: 13);
    switch (st.phase) {
      case DownloadPhase.idle:
        final info = _info;
        if (info == null) {
          return Text('Ya no hay ninguna descarga en curso.', style: muted);
        }
        // Stripped of headings and the compare link: a URL is no use inside a
        // dialog, and older releases contain nothing else.
        final notes = cleanReleaseNotes(info.notes);
        return Text(
          notes.isEmpty ? 'Hay una versión más reciente disponible.' : notes,
          style: muted,
        );
      case DownloadPhase.downloading:
        return _progressBlock(
          st.progress,
          accent,
          cs,
          caption: _statusLine(st.progress),
          hint: 'Puedes salir de Kivo: la descarga sigue.',
        );
      case DownloadPhase.ready:
        return _progressBlock(
          const DownloadProgress(DownloadStage.done, received: 1, total: 1),
          accent,
          cs,
          caption: 'Listo para instalar',
          hint: 'Pulsa Instalar para continuar.',
        );
      case DownloadPhase.failed:
        final f = kivoErrorCatalog[KivoOp.updateInstall]!;
        return Text(
          '${f.message} (${f.code}).\nPuedes reintentar o bajarla desde el navegador.',
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

  List<Widget> _actions(UpdateDownloadState st) {
    final info = _info;
    switch (st.phase) {
      case DownloadPhase.idle:
        if (info == null) return [_closeButton()];
        return [
          TextButton(
            onPressed: () {
              ref.read(updateControllerProvider).skip(info.version);
              Navigator.pop(context);
            },
            child: const Text('Omitir esta versión'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: info.apkUrl == null
                ? () {
                    ref.read(updateControllerProvider).openInBrowser(info);
                    Navigator.pop(context);
                  }
                : () => _dl.start(info),
            child: Text(info.apkUrl == null ? 'Abrir en navegador' : 'Descargar'),
          ),
        ];
      case DownloadPhase.downloading:
        return [
          TextButton(onPressed: _dl.cancel, child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ocultar'),
          ),
          // Present but inert, so it is obvious where the install will happen.
          const FilledButton(onPressed: null, child: Text('Instalar')),
        ];
      case DownloadPhase.ready:
        return [
          // Without a way out, a downloaded APK you no longer want is
          // permanent: it keeps its 30 MB and keeps claiming the update slot,
          // which is how an updater bug once made itself unfixable in-app.
          TextButton(onPressed: _dl.cancel, child: const Text('Descartar')),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => _install(_dl.install()),
            child: const Text('Instalar'),
          ),
        ];
      case DownloadPhase.failed:
        return [
          if (info == null)
            _closeButton()
          else
            TextButton(
              onPressed: () {
                ref.read(updateControllerProvider).openInBrowser(info);
                Navigator.pop(context);
              },
              child: const Text('Abrir en navegador'),
            ),
          FilledButton(
            onPressed: () => _install(_dl.retry(info)),
            child: const Text('Reintentar'),
          ),
        ];
    }
  }

  Widget _closeButton() => TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      );

  /// Reports the outcome of an install attempt. A null outcome means a fresh
  /// download was queued instead, which the progress block already narrates.
  Future<void> _install(Future<InstallOutcome?> pending) async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await pending;
    if (!mounted || outcome == null) return;
    switch (outcome) {
      case InstallOutcome.started:
        Navigator.pop(context);
      case InstallOutcome.needsPermission:
        messenger.showSnackBar(const SnackBar(
          content: Text('Permite instalar apps para continuar, luego pulsa Instalar.'),
        ));
      case InstallOutcome.failed:
        break; // the dialog already switched to its failed state
    }
  }
}

String _statusLine(DownloadProgress p) {
  final size = p.total > 0
      ? '${_mb(p.received)} / ${_mb(p.total)} MB'
      : '${_mb(p.received)} MB';
  final pct = p.fraction;
  return switch (p.stage) {
    DownloadStage.pending => 'En cola…',
    DownloadStage.pausedNetwork => 'En pausa · esperando conexión',
    DownloadStage.pausedRetry => 'En pausa · reintentando',
    _ => pct == null ? size : '$size · ${(pct * 100).round()} %',
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
