import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/theme/kivo_theme.dart';
import '../state/hud_state.dart';

class HudOverlay extends ConsumerWidget {
  const HudOverlay({super.key});

  String _icon(HudKind k, HudState hud) {
    switch (k) {
      case HudKind.brightness:
        return KivoIcons.brightness;
      case HudKind.volume:
        return KivoIcons.volume;
      case HudKind.seek:
        return hud.value < 0 ? KivoIcons.fastRewind : KivoIcons.fastForward;
      case HudKind.speed:
        return KivoIcons.speed;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hud = ref.watch(hudProvider);
    if (hud == null) return const SizedBox.shrink();
    final showBar = hud.kind == HudKind.brightness || hud.kind == HudKind.volume;
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              KivoIcon(_icon(hud.kind, hud), color: KivoColors.gold, size: 30),
              const SizedBox(height: 8),
              Text(hud.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              if (showBar) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(
                    value: hud.value.clamp(0.0, 1.0),
                    backgroundColor: Colors.white24,
                    color: KivoColors.blue,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
