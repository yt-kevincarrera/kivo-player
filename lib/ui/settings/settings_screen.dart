import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/kivo_settings.dart';
import '../../core/settings/settings_provider.dart';
import '../../l10n/l10n.dart';
import '../vault/vault_entry_actions.dart';
import 'sections/about_section.dart';
import 'sections/advanced_playback_section.dart';
import 'sections/backup_section.dart';
import 'sections/equalizer_section.dart';
import 'sections/general_section.dart';
import 'sections/interface_section.dart';
import 'sections/playback_gestures_section.dart';
import 'widgets/setting_tiles.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsRootTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        children: [
          SettingsCard(children: [
            SettingNavRow(
              icon: Icons.tune, title: l10n.settingsGeneralTitle, subtitle: l10n.settingsGeneralNavSubtitle,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GeneralSettingsSection()))),
            SettingNavRow(
              icon: Icons.videogame_asset_outlined,
              title: l10n.settingsPlaybackGesturesTitle,
              subtitle: l10n.settingsPlaybackGesturesNavSubtitle,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlaybackGesturesSection()))),
            SettingNavRow(
              icon: Icons.dashboard_customize_outlined,
              title: l10n.settingsInterfaceTitle,
              subtitle: l10n.settingsInterfaceNavSubtitle,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InterfaceSettingsSection()))),
            SettingNavRow(
              icon: Icons.play_circle_outline,
              title: l10n.settingsAdvancedPlaybackTitle,
              subtitle: l10n.settingsAdvancedPlaybackNavSubtitle,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdvancedPlaybackSection()))),
            SettingNavRow(
              icon: Icons.equalizer_rounded,
              title: l10n.settingsEqualizerTitle,
              subtitle: l10n.settingsEqualizerNavSubtitle,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EqualizerSection()))),
            SettingNavRow(
              icon: Icons.save_outlined,
              title: l10n.settingsBackupTitle,
              subtitle: l10n.settingsBackupNavSubtitle,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BackupSection()))),
            SettingNavRow(
              icon: Icons.info_outline, title: l10n.settingsAboutTitle, subtitle: l10n.settingsAboutNavSubtitle,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutSection()))),
            if (!ref.watch(settingsProvider).vaultEntranceHidden)
              SettingNavRow(
                // 'Vault' is a proper noun (product name), never translated.
                icon: Icons.lock_outline, title: 'Vault', subtitle: l10n.settingsVaultNavSubtitle,
                onTap: () => openVault(context)),
          ]),
          const SizedBox(height: 18),
          _ResetTile(
            onReset: () => ref.read(settingsProvider.notifier).set(KivoSettings.defaults()),
          ),
        ],
      ),
    );
  }
}

class _ResetTile extends StatelessWidget {
  final VoidCallback onReset;
  const _ResetTile({required this.onReset});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.settingsResetAllTitle),
            content: Text(l10n.settingsResetAllBody),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.commonCancel)),
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.settingsResetAction)),
            ],
          ),
        );
        if (ok == true) onReset();
      },
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(l10n.settingsResetAllTitle,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.error)),
      ),
    );
  }
}
