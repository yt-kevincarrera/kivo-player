import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/kivo_failure.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/update/update_download_controller.dart';
import '../../../core/update/update_providers.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/app_installer_provider.dart';
import '../../update/update_dialog.dart';
import '../../widgets/failure_snack_bar.dart';
import '../widgets/setting_tiles.dart';
import 'error_log_section.dart';

class AboutSection extends ConsumerStatefulWidget {
  const AboutSection({super.key});
  @override
  ConsumerState<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends ConsumerState<AboutSection> {
  bool _checking = false;
  late final Future<String> _versionFuture;

  /// Held from initState so dispose never has to touch ref.
  late final UpdateDownloadNotifier _dl;

  @override
  void initState() {
    super.initState();
    _versionFuture = ref.read(appInstallerProvider).appVersion();
    // Without this the row would render whatever the provider last saw, which
    // for a download started earlier in the session means a permanent
    // "Descargando" even after the APK has landed.
    _dl = ref.read(updateDownloadProvider.notifier);
    _dl.startWatching();
  }

  @override
  void dispose() {
    _dl.stopWatching();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final result = await ref
          .read(updateControllerProvider)
          .check(manual: true);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final l10n = context.l10n;
      switch (result.status) {
        case UpdateStatus.available:
          showUpdateDialog(context, result.info!);
        case UpdateStatus.upToDate:
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.settingsAboutUpToDateSnackbar)),
          );
        case UpdateStatus.error:
          showFailureSnackBar(context, KivoOp.updateCheck);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// The pending-download row and the manual check, in that order.
  ///
  /// The pending row is the way back into a download the user hid, so a
  /// finished APK is never stranded behind a network round-trip to GitHub. It
  /// is an ADDITION, never a replacement: when it replaced the check row, a
  /// stuck download locked the user out of ever finding a newer release — and
  /// that is exactly how a bug in the updater made itself unfixable from
  /// inside the app.
  List<Widget> _updateTiles(BuildContext context, ColorScheme cs) {
    final l10n = context.l10n;
    final pending = ref.watch(updateDownloadProvider);
    // The version is missing only if settings were cleared under a live
    // download, so it belongs in the subtitle rather than the title.
    final v = pending.version;
    return [
      switch (pending.phase) {
        DownloadPhase.downloading => ListTile(
          leading: Icon(Icons.downloading_outlined, color: cs.onSurfaceVariant),
          title: Text(l10n.settingsAboutDownloading),
          subtitle: Text(
            v == null
                ? l10n.settingsAboutDownloadingSubtitleNoVersion
                : l10n.settingsAboutDownloadingSubtitleWithVersion(v),
          ),
          onTap: () => showPendingUpdateDialog(context),
        ),
        DownloadPhase.ready => ListTile(
          leading: Icon(Icons.download_done_outlined, color: cs.secondary),
          title: Text(l10n.settingsAboutReady),
          subtitle: Text(
            v == null
                ? l10n.settingsAboutReadySubtitleNoVersion
                : l10n.settingsAboutReadySubtitleWithVersion(v),
          ),
          onTap: () => showPendingUpdateDialog(context),
        ),
        DownloadPhase.idle || DownloadPhase.failed => const SizedBox.shrink(),
      },
      _checkTile(context, cs),
    ];
  }

  Widget _checkTile(BuildContext context, ColorScheme cs) {
    return ListTile(
      leading: _checking
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.secondary,
              ),
            )
          : Icon(Icons.system_update_outlined, color: cs.onSurfaceVariant),
      title: Text(context.l10n.settingsAboutCheckForUpdates),
      onTap: _checking ? null : _check,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final auto = ref.watch(settingsProvider.select((s) => s.autoCheckUpdates));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAboutTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 28),
        children: [
          Center(
            child: Column(
              children: [
                Text(
                  'Kivo',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                FutureBuilder<String>(
                  future: _versionFuture,
                  builder: (_, snap) => Text(
                    l10n.settingsAboutVersion(snap.data ?? '…'),
                    style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.settingsAboutTagline,
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.settingsAboutByAuthor,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  'kevin.ccdo@gmail.com',
                  style: TextStyle(fontSize: 12.5, color: cs.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          ..._updateTiles(context, cs),
          SettingSwitch(
            title: l10n.settingsAboutAutoCheck,
            subtitle: l10n.settingsAboutAutoCheckSubtitle,
            value: auto,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .set(ref.read(settingsProvider).copyWith(autoCheckUpdates: v)),
          ),
          const SizedBox(height: 20),
          SettingsCard(
            children: [
              SettingNavRow(
                icon: Icons.bug_report_outlined,
                title: l10n.settingsAboutErrorLogTitle,
                subtitle: l10n.settingsAboutErrorLogSubtitle,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ErrorLogSection()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
