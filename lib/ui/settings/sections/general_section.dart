import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../widgets/setting_tiles.dart';
import 'hidden_folders_section.dart';

class GeneralSettingsSection extends ConsumerWidget {
  const GeneralSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: const Text('General')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _label(context, 'Apariencia'),
          SettingsCard(children: [
            SettingSegmented<String>(
              title: 'Tema',
              subtitle: 'Claro, oscuro o según el sistema',
              options: const [('auto', 'Auto'), ('dark', 'Oscuro'), ('light', 'Claro')],
              value: s.themeMode,
              onChanged: (v) => n.set(s.copyWith(themeMode: v)),
            ),
            SettingColor(
              title: 'Color de acento',
              value: s.accentColor,
              onChanged: (v) => n.set(s.copyWith(accentColor: v)),
            ),
            SettingSegmented<String>(
              title: 'Iconos',
              subtitle: 'Duotono o plano (blanco)',
              options: const [('duotone', 'Duotono'), ('flat', 'Plano')],
              value: s.iconStyle,
              onChanged: (v) => n.set(s.copyWith(iconStyle: v)),
            ),
            SettingSegmented<String>(
              title: l10n.settingsLanguage,
              options: [
                ('system', l10n.settingsLanguageSystem),
                ('es', l10n.settingsLanguageSpanish),
                ('en', l10n.settingsLanguageEnglish),
              ],
              value: s.locale,
              onChanged: (v) => n.set(s.copyWith(locale: v)),
            ),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Interacción'),
          SettingsCard(children: [
            SettingSwitch(
              title: 'Háptica en gestos',
              subtitle: 'Vibración sutil al cruzar umbrales',
              value: s.hapticsOnGestures,
              onChanged: (v) => n.set(s.copyWith(hapticsOnGestures: v)),
            ),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Biblioteca'),
          SettingsCard(children: [
            SettingNavRow(
              icon: Icons.folder_off_outlined,
              title: 'Carpetas ocultas',
              subtitle: 'Carpetas que no aparecen en tu biblioteca',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const HiddenFoldersSection())),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 10.5, letterSpacing: 1.4, fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.secondary)),
      );
}
