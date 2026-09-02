import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';
import '../../../player/audio/equalizer.dart';
import '../../../player/audio/equalizer_controller.dart';
import '../widgets/setting_tiles.dart';

/// The equalizer screen: an enable switch, four presets, ten band sliders and
/// a preamp slider. Reachable from Ajustes (its own row), and from
/// the player's ⋮ menu for adjusting while listening — same screen either
/// way, same [equalizerProvider].
class EqualizerSection extends ConsumerStatefulWidget {
  const EqualizerSection({super.key});

  @override
  ConsumerState<EqualizerSection> createState() => _EqualizerSectionState();
}

class _EqualizerSectionState extends ConsumerState<EqualizerSection> {
  // deactivate(), not dispose(): a ConsumerStatefulElement tears its `ref`
  // down before dispose() runs (Flutter unmounts the element, then calls
  // State.dispose() — by then `context.mounted` is already false and any
  // `ref.read` throws), but the element is still fully active during
  // deactivate(). The notifier itself is process-lifetime and keeps
  // debouncing on its own either way; this just means the last drag before
  // leaving the screen reaches mpv and disk right away instead of waiting
  // out the 120ms window with nobody left around to trigger it early.
  @override
  void deactivate() {
    ref.read(equalizerProvider.notifier).flush();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final eq = ref.watch(equalizerProvider);
    final notifier = ref.read(equalizerProvider.notifier);
    final preset = presetNameFor(eq);

    return Scaffold(
      appBar: AppBar(title: const Text('Ecualizador')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          SettingsCard(children: [
            SettingSwitch(
              title: 'Ecualizador',
              subtitle: 'Aplica la curva de graves, voz y agudos al audio',
              value: eq.enabled,
              onChanged: notifier.setEnabled,
            ),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Preajustes'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in equalizerPresetNames)
                _PresetChip(
                  label: name,
                  selected: preset == name,
                  accent: accent,
                  onTap: () => notifier.applyPreset(name),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _label(context, 'Bandas'),
          SettingsCard(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < equalizerBandsHz.length; i++)
                    Expanded(
                      child: _BandSlider(
                        hz: equalizerBandsHz[i],
                        db: eq.gainsDb[i],
                        accent: accent,
                        onChanged: (v) => notifier.setBand(i, v),
                      ),
                    ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _label(context, 'Preamplificación'),
          SettingsCard(children: [
            SettingSlider(
              title: 'Ganancia general',
              value: eq.preampDb,
              min: equalizerMinDb,
              max: equalizerMaxDb,
              divisions:
                  ((equalizerMaxDb - equalizerMinDb) / equalizerStepDb).round(),
              label: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
              onChanged: notifier.setPreamp,
            ),
          ]),
          const SizedBox(height: 18),
          _ResetTile(onTap: notifier.resetCurve),
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

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? onAccent(accent) : cs.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// One band: the dB reading above, a vertical slider, the frequency label
/// below. `RotatedBox` turns the ordinary horizontal [Slider] vertical —
/// simplest way to get a vertical drag without a bespoke gesture handler.
class _BandSlider extends StatelessWidget {
  final int hz;
  final double db;
  final Color accent;
  final ValueChanged<double> onChanged;
  const _BandSlider({
    required this.hz,
    required this.db,
    required this.accent,
    required this.onChanged,
  });

  String get _freqLabel =>
      hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}K' : '$hz';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          db.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            color: db == 0 ? cs.onSurfaceVariant : accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        SizedBox(
          height: 120,
          width: 28,
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                overlayShape: SliderComponentShape.noOverlay,
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: db.clamp(equalizerMinDb, equalizerMaxDb),
                min: equalizerMinDb,
                max: equalizerMaxDb,
                divisions:
                    ((equalizerMaxDb - equalizerMinDb) / equalizerStepDb).round(),
                activeColor: accent,
                inactiveColor: cs.onSurfaceVariant.withValues(alpha: 0.3),
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _freqLabel,
          style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ResetTile extends StatelessWidget {
  final VoidCallback onTap;
  const _ResetTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text('Restablecer',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.secondary)),
      ),
    );
  }
}
