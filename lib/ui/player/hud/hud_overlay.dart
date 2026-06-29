import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../state/hud_state.dart';

class HudOverlay extends ConsumerWidget {
  const HudOverlay({super.key});

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
        return _buildEdgeCapsule(
          hud: hud,
          accent: accent,
          alignLeft: true,
        );
      case HudKind.volume:
        return _buildEdgeCapsule(
          hud: hud,
          accent: accent,
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

  Widget _buildEdgeCapsule({
    required HudState hud,
    required Color accent,
    required bool alignLeft,
  }) {
    final isBrightness = hud.kind == HudKind.brightness;
    final boosting = hud.label.contains('boost');
    final value = hud.value;

    // Volume: discrete icon with crossfade on bucket change.
    // Brightness: continuous parametric icon, no AnimatedSwitcher.
    Widget reactiveIcon;
    if (isBrightness) {
      reactiveIcon = KivoIcon(
        KivoIcons.brightnessFor(value),
        size: 30,
        color: Colors.white,
      );
    } else {
      final iconStr = value <= 0.02
          ? KivoIcons.volumeMute
          : value < 0.34
              ? KivoIcons.volumeLow
              : KivoIcons.volume;
      reactiveIcon = AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(anim),
            child: child,
          ),
        ),
        child: KivoIcon(
          iconStr,
          key: ValueKey(iconStr),
          size: 30,
          color: boosting ? accent : Colors.white,
        ),
      );
    }

    // Bar fill tracks drag directly — no animation.
    final barFill = FractionallySizedBox(
      heightFactor: value.clamp(0.0, 1.0),
      child: Container(
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );

    final bar = SizedBox(
      width: 8,
      height: 150,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // track
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          // fill — direct, no animation
          barFill,
        ],
      ),
    );

    final numeric = Text(
      hud.label,
      style: TextStyle(
        color: boosting ? accent : Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 15,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    final capsule = Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          reactiveIcon,
          const SizedBox(height: 14),
          bar,
          const SizedBox(height: 12),
          numeric,
        ],
      ),
    );

    // Subtle scale-in pop on appearance (cheap — runs once per show).
    final animated = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.9, end: 1.0),
      duration: const Duration(milliseconds: 140),
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: capsule,
    );

    return Align(
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.only(
          left: alignLeft ? 20 : 0,
          right: alignLeft ? 0 : 20,
        ),
        child: animated,
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
