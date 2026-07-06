import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../widgets/setting_tiles.dart';
import '../widgets/setting_choice.dart';
import '../widgets/setting_corner_picker.dart';

class InterfaceSettingsSection extends ConsumerWidget {
  const InterfaceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Interfaz')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _label(context, 'Controles'),
          SettingsCard(children: [
            SettingStepper(
              title: 'Auto-ocultar controles',
              value: (s.controlsAutoHideMs / 1000).round().clamp(1, 10),
              min: 1, max: 10, step: 1, label: (v) => '$v s',
              onChanged: (v) => n.set(s.copyWith(controlsAutoHideMs: v * 1000))),
            SettingSwitch(
              title: 'Recordar orientación entre videos', value: s.rememberOrientationLock,
              onChanged: (v) => n.set(s.copyWith(rememberOrientationLock: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Video'),
          SettingsCard(children: [
            SettingSegmented<String>(
              title: 'Aspecto por defecto', value: s.defaultAspectMode,
              options: const [('fit', 'Ajustar'), ('fill', 'Llenar'), ('stretch', 'Estirar')],
              onChanged: (v) => n.set(s.copyWith(defaultAspectMode: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Overlay de información'),
          SettingsCard(children: [
            SettingSwitch(
              title: 'Mostrar overlay de info', value: s.showInfoOverlay,
              onChanged: (v) => n.set(s.copyWith(showInfoOverlay: v))),
            if (s.showInfoOverlay) ...[
              SettingChoice<String>(
                title: 'Contenido', value: s.infoOverlayContent,
                options: const [('name_time', 'Nombre y tiempo'), ('name', 'Solo nombre'), ('remaining', 'Tiempo restante')],
                onChanged: (v) => n.set(s.copyWith(infoOverlayContent: v))),
              SettingCornerPicker(
                title: 'Esquina', value: s.infoOverlayCorner,
                onChanged: (v) => n.set(s.copyWith(infoOverlayCorner: v))),
            ],
          ]),
          const SizedBox(height: 16),
          _label(context, 'Biblioteca'),
          SettingsCard(children: [
            SettingSegmented<int>(
              title: 'Columnas por defecto', value: s.libraryColumns,
              options: const [(1, '1'), (2, '2'), (3, '3')],
              onChanged: (v) => n.set(s.copyWith(libraryColumns: v))),
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
