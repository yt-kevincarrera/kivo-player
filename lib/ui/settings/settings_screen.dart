import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/kivo_settings.dart';
import '../../core/settings/settings_provider.dart';
import 'sections/about_section.dart';
import 'sections/advanced_playback_section.dart';
import 'sections/general_section.dart';
import 'sections/interface_section.dart';
import 'sections/playback_gestures_section.dart';
import 'widgets/setting_tiles.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        children: [
          SettingsCard(children: [
            SettingNavRow(
              icon: Icons.tune, title: 'General', subtitle: 'Tema, color de acento, háptica',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GeneralSettingsSection()))),
            SettingNavRow(
              icon: Icons.videogame_asset_outlined,
              title: 'Reproducción y gestos',
              subtitle: 'Saltos, sensibilidades, velocidad',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlaybackGesturesSection()))),
            SettingNavRow(
              icon: Icons.dashboard_customize_outlined,
              title: 'Interfaz',
              subtitle: 'Controles, overlay, aspecto, columnas',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InterfaceSettingsSection()))),
            SettingNavRow(
              icon: Icons.play_circle_outline,
              title: 'Reproducción avanzada',
              subtitle: 'Continuar, autoplay, subtítulos, PiP',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdvancedPlaybackSection()))),
            SettingNavRow(
              icon: Icons.info_outline, title: 'Acerca de', subtitle: 'Versión $kAppVersion',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutSection()))),
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
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Restablecer valores'),
            content: const Text('¿Restablecer todos los ajustes a sus valores por defecto?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Restablecer')),
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
        child: Text('Restablecer valores',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.error)),
      ),
    );
  }
}
