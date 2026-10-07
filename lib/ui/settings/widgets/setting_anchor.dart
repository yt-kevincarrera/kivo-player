import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/settings_provider.dart';
import '../search/settings_search_state.dart';

/// Marks a setting as a search target. When a search result opens this
/// section asking for [id], the anchor waits for the page transition to
/// land, scrolls itself into view and flashes once in the accent colour.
class SettingAnchor extends ConsumerStatefulWidget {
  final String id;
  final Widget child;

  /// For targets that don't sit inside a [SettingsCard] (which already clips
  /// its rows), so the flash gets the same rounded corners as its neighbours.
  final BorderRadius? borderRadius;

  const SettingAnchor({super.key, required this.id, required this.child, this.borderRadius});

  @override
  ConsumerState<SettingAnchor> createState() => _SettingAnchorState();
}

class _SettingAnchorState extends ConsumerState<SettingAnchor> with SingleTickerProviderStateMixin {
  late final AnimationController _flash =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  // Quick rise, a beat at full, slow fade: long enough to find it, short
  // enough not to read as a selected state.
  late final Animation<double> _strength = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 15),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 25),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 60),
  ]).animate(_flash);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeReveal());
  }

  Future<void> _maybeReveal() async {
    if (!mounted || ref.read(settingsHighlightProvider) != widget.id) return;
    ref.read(settingsHighlightProvider.notifier).state = null;

    // Flashing mid-slide would be over before the page stops moving.
    final route = ModalRoute.of(context)?.animation;
    if (route != null && route.status != AnimationStatus.completed) {
      final landed = Completer<void>();
      void onStatus(AnimationStatus s) {
        if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
          route.removeStatusListener(onStatus);
          if (!landed.isCompleted) landed.complete();
        }
      }

      route.addStatusListener(onStatus);
      await landed.future;
    }
    if (!mounted) return;
    await Scrollable.ensureVisible(context,
        alignment: 0.35, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    if (!mounted) return;
    _flash.forward(from: 0);
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(ref.watch(settingsProvider.select((s) => s.accentColor)));
    return AnimatedBuilder(
      animation: _strength,
      child: widget.child,
      // Always the same DecoratedBox, transparent at rest: swapping one in
      // and out would change the tree shape and remount the control below
      // (a slider mid-drag would lose its gesture).
      builder: (context, child) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.24 * _strength.value), borderRadius: widget.borderRadius),
        child: child,
      ),
    );
  }
}
