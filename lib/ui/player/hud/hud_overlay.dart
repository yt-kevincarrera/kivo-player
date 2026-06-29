import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../state/hud_state.dart';

class HudOverlay extends ConsumerWidget {
  const HudOverlay({super.key});

  String _volumeIcon(double value) {
    if (value <= 0.02) return KivoIcons.volumeMute;
    if (value < 0.34) return KivoIcons.volumeLow;
    return KivoIcons.volume;
  }

  String _brightnessIcon(double value) {
    if (value < 0.4) return KivoIcons.brightnessLow;
    return KivoIcons.brightness;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final hud = ref.watch(hudProvider);
    if (hud == null) return const SizedBox.shrink();

    return IgnorePointer(child: _buildHud(hud, accent));
  }

  Widget _buildHud(HudState hud, Color accent) {
    switch (hud.kind) {
      case HudKind.brightness:
        return _buildEdgeBar(
          hud: hud,
          accent: accent,
          icon: _brightnessIcon(hud.value),
          alignLeft: true,
        );
      case HudKind.volume:
        return _buildEdgeBar(
          hud: hud,
          accent: accent,
          icon: _volumeIcon(hud.value),
          alignLeft: false,
        );
      case HudKind.seek:
        return _buildChip(
          hud: hud,
          accent: accent,
          icon: hud.value < 0 ? KivoIcons.fastRewind : KivoIcons.fastForward,
        );
      case HudKind.speed:
        return _buildChip(hud: hud, accent: accent, icon: KivoIcons.speed);
    }
  }

  Widget _buildEdgeBar({
    required HudState hud,
    required Color accent,
    required String icon,
    required bool alignLeft,
  }) {
    final isBoost = hud.kind == HudKind.volume && hud.label.contains('boost');
    final labelColor = isBoost ? accent : Colors.white;

    return Align(
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(
          left: alignLeft ? 24 : 0,
          right: alignLeft ? 0 : 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            KivoIcon(icon, size: 30, color: Colors.white),
            const SizedBox(height: 12),
            Container(
              width: 8,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: hud.value.clamp(0.0, 1.0),
                  child: Container(
                    width: 8,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              hud.label,
              style: TextStyle(
                color: labelColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip({
    required HudState hud,
    required Color accent,
    required String icon,
  }) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KivoIcon(icon, size: 24, color: accent),
            const SizedBox(width: 8),
            Text(
              hud.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
