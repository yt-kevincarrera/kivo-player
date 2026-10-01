import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';

/// What Kivo does and does not do with your data, in plain words. Every
/// claim here is something the code actually does — change the code, change
/// this page.
class PrivacySection extends StatelessWidget {
  const PrivacySection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    Widget block(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: cs.secondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface)),
                    const SizedBox(height: 4),
                    Text(body,
                        style: TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.privacyTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          Text(l10n.privacyIntro,
              style: TextStyle(
                  fontSize: 15, height: 1.45, color: cs.onSurface)),
          const SizedBox(height: 24),
          block(Icons.cloud_sync_outlined, l10n.privacyNetworkTitle,
              l10n.privacyNetworkBody),
          block(Icons.bug_report_outlined, l10n.privacyReportsTitle,
              l10n.privacyReportsBody),
          block(Icons.cloud_off_outlined, l10n.privacyBackupTitle,
              l10n.privacyBackupBody),
          block(Icons.verified_user_outlined, l10n.privacyPermissionsTitle,
              l10n.privacyPermissionsBody),
        ],
      ),
    );
  }
}
