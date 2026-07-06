import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../widgets/setting_tiles.dart';
import '../widgets/setting_speed_list.dart';

class PlaybackGesturesSection extends ConsumerWidget {
  const PlaybackGesturesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    String sec(int v) => '$v s';
    String x1(double v) => '${v.toStringAsFixed(1)}×';
    String x2(double v) => '${v.toStringAsFixed(2)}×';

    return Scaffold(
      appBar: AppBar(title: const Text('Reproducción y gestos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _label(context, 'Doble toque'),
          SettingsCard(children: [
            SettingStepper(
                title: 'Saltar atrás', value: s.doubleTapSkipLeft, min: 5, max: 60, step: 5,
                label: sec, onChanged: (v) => n.set(s.copyWith(doubleTapSkipLeft: v))),
            SettingStepper(
                title: 'Saltar adelante', value: s.doubleTapSkipRight, min: 5, max: 60, step: 5,
                label: sec, onChanged: (v) => n.set(s.copyWith(doubleTapSkipRight: v))),
            SettingSwitch(
                title: 'Pausar con doble toque al centro', value: s.doubleTapCenterPause,
                onChanged: (v) => n.set(s.copyWith(doubleTapCenterPause: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Salto y seek'),
          SettingsCard(children: [
            SettingStepper(
                title: 'Salto de los botones ±', value: s.centerSkipSeconds, min: 5, max: 60, step: 5,
                label: sec, onChanged: (v) => n.set(s.copyWith(centerSkipSeconds: v))),
            SettingSwitch(
                title: 'Buscar deslizando en horizontal', value: s.horizontalSeek,
                onChanged: (v) => n.set(s.copyWith(horizontalSeek: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Sensibilidad de gestos'),
          SettingsCard(children: [
            SettingSlider(
                title: 'Brillo', value: s.brightnessSensitivity, min: 0.5, max: 2.0, divisions: 15,
                label: x1, onChanged: (v) => n.set(s.copyWith(brightnessSensitivity: v))),
            SettingSlider(
                title: 'Volumen', value: s.volumeSensitivity, min: 0.5, max: 2.0, divisions: 15,
                label: x1, onChanged: (v) => n.set(s.copyWith(volumeSensitivity: v))),
            SettingSlider(
                title: 'Seek', value: s.seekSensitivity, min: 0.5, max: 2.0, divisions: 15,
                label: x1, onChanged: (v) => n.set(s.copyWith(seekSensitivity: v))),
            SettingStepper(
                title: 'Boost máximo de volumen', value: s.volumeBoostMax, min: 100, max: 200, step: 10,
                label: (v) => '$v %', onChanged: (v) => n.set(s.copyWith(volumeBoostMax: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Velocidad'),
          SettingsCard(children: [
            SettingSwitch(
                title: 'Recordar velocidad entre videos', value: s.rememberSpeed,
                onChanged: (v) => n.set(s.copyWith(rememberSpeed: v))),
            SettingSlider(
                title: 'Velocidad al mantener (izquierda)', value: s.holdLeftSpeed, min: 1.0, max: 4.0,
                divisions: 12, label: x2, onChanged: (v) => n.set(s.copyWith(holdLeftSpeed: v))),
            SettingSlider(
                title: 'Velocidad máxima', value: s.holdRightMax, min: 2.0, max: 8.0, divisions: 12,
                label: x1, onChanged: (v) => n.set(s.copyWith(holdRightMax: v))),
            SettingSwitch(
                title: 'Al soltar el acelerador, volver a la velocidad anterior',
                value: s.holdRightReleaseToNormal,
                onChanged: (v) => n.set(s.copyWith(holdRightReleaseToNormal: v))),
            SettingSegmented<double>(
                title: 'Paso fino de velocidad', value: s.speedFineStep,
                options: const [(0.01, '0.01×'), (0.05, '0.05×'), (0.1, '0.10×'), (0.25, '0.25×')],
                onChanged: (v) => n.set(s.copyWith(speedFineStep: v))),
            SettingSpeedList(
                title: 'Velocidades preseleccionadas',
                subtitle: 'Las que aparecen en el panel de velocidad',
                values: s.speedPresets, min: 0.25, max: 4.0,
                onChanged: (v) => n.set(s.copyWith(speedPresets: v))),
            SettingSpeedList(
                title: 'Escalones del acelerador (hold derecho)',
                subtitle: 'La escalera de velocidades al mantener a la derecha',
                values: s.holdRightDetents, min: 1.0, max: 8.0,
                onChanged: (v) => n.set(s.copyWith(holdRightDetents: v))),
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
