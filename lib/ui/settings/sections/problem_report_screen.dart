import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_log_provider.dart';
import '../../../core/report/problem_report.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/app_installer_provider.dart';

/// "Reportar un problema": the whole report, visible and editable before it
/// goes anywhere — Kivo never sends anything by itself.
class ProblemReportScreen extends ConsumerStatefulWidget {
  const ProblemReportScreen({super.key});

  @override
  ConsumerState<ProblemReportScreen> createState() =>
      _ProblemReportScreenState();
}

class _ProblemReportScreenState extends ConsumerState<ProblemReportScreen> {
  final _description = TextEditingController();
  late final Future<({String version, int sdk, String model})> _device;

  @override
  void initState() {
    super.initState();
    final installer = ref.read(appInstallerProvider);
    _device = () async {
      final results = await Future.wait<Object>([
        installer.appVersion(),
        installer.androidSdk(),
        installer.deviceModel(),
      ]);
      return (
        version: results[0] as String,
        sdk: results[1] as int,
        model: results[2] as String,
      );
    }();
    _description.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _open(Uri url) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.reportOpenFailedSnackbar;
    try {
      await ref.read(appInstallerProvider).openUrl(url.toString());
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final entries = ref.read(errorLogProvider).entries();
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.reportTitle)),
      body: FutureBuilder(
        future: _device,
        builder: (context, snap) {
          final d = snap.data;
          final report = buildProblemReport(
            appVersion: d?.version ?? '…',
            androidSdk: d?.sdk ?? 0,
            deviceModel: d?.model ?? '',
            locale: locale,
            entries: entries,
            description: _description.text,
          );
          final subject = problemReportSubject(d?.version ?? '', entries);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              TextField(
                key: const Key('report-description'),
                controller: _description,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: l10n.reportDescribeHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.reportPreviewLabel.toUpperCase(),
                style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                    color: cs.secondary),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  report,
                  key: const Key('report-preview'),
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      height: 1.4,
                      color: cs.onSurface),
                ),
              ),
              const SizedBox(height: 8),
              Text(l10n.reportPreviewHint,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _open(emailUrl(subject, report)),
                icon: const Icon(Icons.email_outlined),
                label: Text(l10n.reportSendEmail),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _open(issueUrl(subject, report)),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(l10n.reportOpenGithub),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final copied = l10n.reportCopiedSnackbar;
                  await Clipboard.setData(ClipboardData(text: report));
                  messenger.showSnackBar(SnackBar(content: Text(copied)));
                },
                icon: const Icon(Icons.copy_rounded),
                label: Text(l10n.reportCopy),
              ),
            ],
          );
        },
      ),
    );
  }
}
