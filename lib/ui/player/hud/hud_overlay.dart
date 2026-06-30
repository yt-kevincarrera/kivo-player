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
        // brightness → RIGHT edge (opposite the left-side finger)
        return _buildEdgeCapsule(
          hud: hud,
          accent: accent,
          alignLeft: false,
        );
      case HudKind.volume:
        // volume → LEFT edge (opposite the right-side finger)
        return _buildEdgeCapsule(
          hud: hud,
          accent: accent,
          alignLeft: true,
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
    final value = hud.value;
    final boosting = hud.kind == HudKind.volume && value > 1.0;
    final fill = value.clamp(0.0, 1.0);

    // Volume: discrete icon with crossfade on bucket change (AnimatedSwitcher).
    // Brightness: continuous parametric icon, rendered directly (no AnimatedSwitcher).
    Widget reactiveIcon;
    if (isBrightness) {
      reactiveIcon = KivoIcon(
        KivoIcons.brightnessFor(value),
        size: 28,
        color: Colors.white,
      );
    } else {
      final iconStr = fill <= 0.02
          ? KivoIcons.volumeMute
          : fill < 0.5
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
          size: 28,
          color: boosting ? accent : Colors.white,
        ),
      );
    }

    // Segmented meter: 12 normal segments (0-100%) + optional boost zone above.
    // For volume only: 3 boost segments above a 100%-tick line, lit only when > 1.0.
    final normalLit = (fill * 12).round();
    final isVolume = hud.kind == HudKind.volume;
    final boostLit = (isVolume && value > 1.0)
        ? (((value - 1.0) / 0.5).clamp(0.0, 1.0) * 3).round()
        : 0;

    Widget seg(bool lit) => Container(
          width: 22,
          height: 8,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: lit ? accent : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(2.5),
          ),
        );

    final meter = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isVolume) ...[
          for (var b = 2; b >= 0; b--) seg(b < boostLit),
          Container(
            width: 14,
            height: 2,
            margin: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
        for (var i = 11; i >= 0; i--) seg(i < normalLit),
      ],
    );

    final numeric = SizedBox(
      width: 44,
      child: Text(
        hud.label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: boosting ? accent : Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );

    final capsule = Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          reactiveIcon,
          const SizedBox(height: 12),
          SizedBox(height: isVolume ? 200 : 150, child: meter),
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
    // Upper third, not centered — the centered play/skip controls would
    // otherwise overlap the seek/speed chip while controls are visible.
    return Align(
      alignment: const Alignment(0, -0.55),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KivoIcon(icon, size: 24, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              hud.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
