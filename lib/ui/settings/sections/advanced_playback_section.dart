import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../widgets/setting_tiles.dart';
import '../widgets/setting_choice.dart';

class AdvancedPlaybackSection extends ConsumerWidget {
  const AdvancedPlaybackSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);

    List<(String?, String)> langOptions(String? current) => [
          (null, 'Automático'),
          if (current != null) (current, '$current (elegido)'),
        ];

    return Scaffold(
      appBar: AppBar(title: const Text('Reproducción avanzada')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _label(context, 'Continuar viendo'),
          SettingsCard(children: [
            SettingChoice<String>(
              title: 'Al reabrir un video', value: s.resumeBehavior,
              options: const [('auto', 'Automático'), ('ask', 'Preguntar'), ('off', 'Desactivado')],
              onChanged: (v) => n.set(s.copyWith(resumeBehavior: v))),
            SettingStepper(
              title: 'Mínimo para recordar posición', value: s.resumeMinSeconds,
              min: 0, max: 120, step: 5, label: (v) => '$v s',
              onChanged: (v) => n.set(s.copyWith(resumeMinSeconds: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Reproducción'),
          SettingsCard(children: [
            SettingSwitch(
              title: 'Reproducir el siguiente automáticamente', value: s.autoplayNext,
              onChanged: (v) => n.set(s.copyWith(autoplayNext: v))),
            SettingSwitch(
              title: 'Miniatura flotante (PiP) al salir al inicio', value: s.pipAutoOnHome,
              onChanged: (v) => n.set(s.copyWith(pipAutoOnHome: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Subtítulos y audio'),
          SettingsCard(children: [
            SettingSwitch(
              title: 'Activar subtítulos por defecto', value: s.subtitlesEnabledByDefault,
              onChanged: (v) => n.set(s.copyWith(subtitlesEnabledByDefault: v))),
            SettingChoice<String?>(
              title: 'Idioma de subtítulos preferido',
              subtitle: 'Se fija al elegir una pista; aquí puedes volver a Automático',
              value: s.preferredSubtitleLanguage, options: langOptions(s.preferredSubtitleLanguage),
              onChanged: (v) => n.set(s.copyWith(preferredSubtitleLanguage: v))),
            SettingChoice<String?>(
              title: 'Idioma de audio preferido',
              subtitle: 'Se fija al elegir una pista; aquí puedes volver a Automático',
              value: s.preferredAudioLanguage, options: langOptions(s.preferredAudioLanguage),
              onChanged: (v) => n.set(s.copyWith(preferredAudioLanguage: v))),
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
