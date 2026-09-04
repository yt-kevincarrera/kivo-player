import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../player/tutorial/gesture_map_route.dart';
import '../widgets/setting_tiles.dart';
import '../widgets/setting_speed_list.dart';

class PlaybackGesturesSection extends ConsumerWidget {
  const PlaybackGesturesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final l10n = context.l10n;
    String sec(int v) => '$v s';
    String x1(double v) => '${v.toStringAsFixed(1)}×';
    String x2(double v) => '${v.toStringAsFixed(2)}×';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsPlaybackGesturesTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _label(context, l10n.settingsGesturesGroupLearn),
          SettingsCard(children: [
            SettingNavRow(
              icon: Icons.touch_app_outlined,
              title: l10n.settingsGesturesViewMap,
              subtitle: l10n.settingsGesturesViewMapSubtitle,
              onTap: () => Navigator.of(context).push(gestureMapRoute()),
            ),
          ]),
          const SizedBox(height: 16),
          _label(context, l10n.settingsGesturesGroupDoubleTap),
          SettingsCard(children: [
            SettingStepper(
                title: l10n.settingsGesturesSkipBack, value: s.doubleTapSkipLeft, min: 5, max: 60, step: 5,
                label: sec, onChanged: (v) => n.set(s.copyWith(doubleTapSkipLeft: v))),
            SettingStepper(
                title: l10n.settingsGesturesSkipForward, value: s.doubleTapSkipRight, min: 5, max: 60, step: 5,
                label: sec, onChanged: (v) => n.set(s.copyWith(doubleTapSkipRight: v))),
            SettingSwitch(
                title: l10n.settingsGesturesDoubleTapPause, value: s.doubleTapCenterPause,
                onChanged: (v) => n.set(s.copyWith(doubleTapCenterPause: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, l10n.settingsGesturesGroupSeek),
          SettingsCard(children: [
            SettingStepper(
                title: l10n.settingsGesturesCenterSkip, value: s.centerSkipSeconds, min: 5, max: 60, step: 5,
                label: sec, onChanged: (v) => n.set(s.copyWith(centerSkipSeconds: v))),
            SettingSwitch(
                title: l10n.settingsGesturesHorizontalSeek, value: s.horizontalSeek,
                onChanged: (v) => n.set(s.copyWith(horizontalSeek: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, l10n.settingsGesturesGroupZoom),
          SettingsCard(children: [
            SettingSwitch(
                title: l10n.settingsGesturesPinchZoom,
                subtitle: l10n.settingsGesturesPinchZoomSubtitle,
                value: s.pinchZoom,
                onChanged: (v) => n.set(s.copyWith(pinchZoom: v))),
            SettingSegmented<double>(
                title: l10n.settingsGesturesZoomMax, value: s.zoomMax,
                options: const [(2.0, '2×'), (4.0, '4×'), (6.0, '6×'), (8.0, '8×')],
                onChanged: (v) => n.set(s.copyWith(zoomMax: v))),
            SettingSegmented<String>(
                title: l10n.settingsGesturesZoomReset,
                subtitle: l10n.settingsGesturesZoomResetSubtitle,
                value: s.zoomResetMode,
                options: [
                  ('exit', l10n.settingsGesturesZoomResetExit),
                  ('video', l10n.settingsGesturesZoomResetVideo),
                  ('never', l10n.settingsGesturesZoomResetNever),
                ],
                onChanged: (v) => n.set(s.copyWith(zoomResetMode: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, l10n.settingsGesturesGroupSensitivity),
          SettingsCard(children: [
            SettingSlider(
                title: l10n.settingsGesturesBrightness, value: s.brightnessSensitivity, min: 0.5, max: 2.0, divisions: 15,
                label: x1, onChanged: (v) => n.set(s.copyWith(brightnessSensitivity: v))),
            SettingSlider(
                title: l10n.settingsGesturesVolume, value: s.volumeSensitivity, min: 0.5, max: 2.0, divisions: 15,
                label: x1, onChanged: (v) => n.set(s.copyWith(volumeSensitivity: v))),
            SettingSlider(
                title: l10n.settingsGesturesSeek, value: s.seekSensitivity, min: 0.5, max: 2.0, divisions: 15,
                label: x1, onChanged: (v) => n.set(s.copyWith(seekSensitivity: v))),
            SettingStepper(
                title: l10n.settingsGesturesVolumeBoostMax, value: s.volumeBoostMax, min: 100, max: 200, step: 10,
                label: (v) => '$v %', onChanged: (v) => n.set(s.copyWith(volumeBoostMax: v))),
          ]),
          const SizedBox(height: 16),
          _label(context, l10n.settingsGesturesGroupSpeed),
          SettingsCard(children: [
            SettingSwitch(
                title: l10n.settingsGesturesRememberSpeed, value: s.rememberSpeed,
                onChanged: (v) => n.set(s.copyWith(rememberSpeed: v))),
            SettingSlider(
                title: l10n.settingsGesturesHoldLeftSpeed, value: s.holdLeftSpeed, min: 1.0, max: 4.0,
                divisions: 12, label: x2, onChanged: (v) => n.set(s.copyWith(holdLeftSpeed: v))),
            SettingSlider(
                title: l10n.settingsGesturesHoldRightMax, value: s.holdRightMax, min: 2.0, max: 8.0, divisions: 12,
                label: x1, onChanged: (v) => n.set(s.copyWith(holdRightMax: v))),
            SettingSwitch(
                title: l10n.settingsGesturesHoldRightRelease,
                value: s.holdRightReleaseToNormal,
                onChanged: (v) => n.set(s.copyWith(holdRightReleaseToNormal: v))),
            SettingSegmented<double>(
                title: l10n.settingsGesturesSpeedFineStep, value: s.speedFineStep,
                options: const [(0.01, '0.01×'), (0.05, '0.05×'), (0.1, '0.10×'), (0.25, '0.25×')],
                onChanged: (v) => n.set(s.copyWith(speedFineStep: v))),
            SettingSpeedList(
                title: l10n.settingsGesturesSpeedPresets,
                subtitle: l10n.settingsGesturesSpeedPresetsSubtitle,
                values: s.speedPresets, min: 0.25, max: 4.0,
                onChanged: (v) => n.set(s.copyWith(speedPresets: v))),
            SettingSpeedList(
                title: l10n.settingsGesturesHoldRightDetents,
                subtitle: l10n.settingsGesturesHoldRightDetentsSubtitle,
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
