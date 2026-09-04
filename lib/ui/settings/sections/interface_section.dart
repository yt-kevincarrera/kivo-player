import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../widgets/setting_tiles.dart';
import '../widgets/setting_choice.dart';
import '../widgets/setting_corner_picker.dart';

class InterfaceSettingsSection extends ConsumerWidget {
  const InterfaceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsInterfaceTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _label(context, l10n.settingsInterfaceGroupControls),
          SettingsCard(children: [
            SettingStepper(
              title: l10n.settingsInterfaceAutoHide,
              value: (s.controlsAutoHideMs / 1000).round().clamp(1, 10),
              min: 1, max: 10, step: 1, label: (v) => '$v s',
              onChanged: (v) => n.set(s.copyWith(controlsAutoHideMs: v * 1000))),
            SettingSwitch(
              title: l10n.settingsInterfaceRememberOrientation, value: s.rememberOrientationLock,
              onChanged: (v) => n.set(s.copyWith(rememberOrientationLock: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, l10n.settingsInterfaceGroupVideo),
          SettingsCard(children: [
            SettingSegmented<String>(
              title: l10n.settingsInterfaceDefaultAspect, value: s.defaultAspectMode,
              options: [
                ('fit', l10n.settingsInterfaceAspectFit),
                ('fill', l10n.settingsInterfaceAspectFill),
                ('stretch', l10n.settingsInterfaceAspectStretch),
              ],
              onChanged: (v) => n.set(s.copyWith(defaultAspectMode: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, l10n.settingsInterfaceGroupOverlay),
          SettingsCard(children: [
            SettingSwitch(
              title: l10n.settingsInterfaceShowOverlay, value: s.showInfoOverlay,
              onChanged: (v) => n.set(s.copyWith(showInfoOverlay: v))),
            if (s.showInfoOverlay) ...[
              SettingChoice<String>(
                title: l10n.settingsInterfaceOverlayContent, value: s.infoOverlayContent,
                options: [
                  ('name_time', l10n.settingsInterfaceOverlayContentNameTime),
                  ('name', l10n.settingsInterfaceOverlayContentNameOnly),
                  ('remaining', l10n.settingsInterfaceOverlayContentRemaining),
                ],
                onChanged: (v) => n.set(s.copyWith(infoOverlayContent: v))),
              SettingCornerPicker(
                title: l10n.settingsInterfaceOverlayCorner, value: s.infoOverlayCorner,
                onChanged: (v) => n.set(s.copyWith(infoOverlayCorner: v))),
            ],
          ]),
          const SizedBox(height: 16),
          _label(context, l10n.settingsGroupLibrary),
          SettingsCard(children: [
            SettingSegmented<int>(
              title: l10n.settingsInterfaceColumns, value: s.libraryColumns,
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
