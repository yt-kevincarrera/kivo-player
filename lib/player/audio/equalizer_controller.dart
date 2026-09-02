import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_provider.dart';
import '../engine/playback_provider.dart';
import '../tracks/track_delay_controller.dart' show trackDelayDebounce;
import 'equalizer.dart';

/// Live equalizer state for the settings screen and the in-player quick
/// panel, seeded from and mirrored into [KivoSettings.equalizer].
///
/// Every setter updates [state] synchronously — sliders must move with the
/// finger, not lag behind it — but the mpv `af` write and the settings
/// persistence are debounced on the trailing edge of [trackDelayDebounce],
/// the same budget `sub-delay`/`audio-delay` use and for the same reason:
/// `setProperty` is a synchronous call on the UI thread, and a slider drag
/// fires many times a second.
class EqualizerNotifier extends Notifier<EqualizerSettings> {
  Timer? _debounce;

  @override
  EqualizerSettings build() {
    ref.onDispose(() => _debounce?.cancel());
    // Watched, not just read once: this also picks up a full settings reset
    // (the "Restablecer valores" tile) without the equalizer screen having
    // to be reopened, and the notifier's own debounced writes below settle
    // back to an identical value, so this never fights the user's own drag.
    return ref.watch(settingsProvider).equalizer;
  }

  void setEnabled(bool enabled) {
    state = state.copyWith(enabled: enabled);
    _schedule();
  }

  void setBand(int index, double db) {
    state = state.withBand(index, db);
    _schedule();
  }

  void setPreamp(double db) {
    state = state.copyWith(preampDb: clampEqualizerDb(db));
    _schedule();
  }

  void applyPreset(String name) {
    final curve = equalizerPresetCurves[name];
    if (curve == null) return;
    state = state.copyWith(gainsDb: List<double>.of(curve));
    _schedule();
  }

  /// Back to a flat curve and zero preamp. Leaves [EqualizerSettings.enabled]
  /// untouched — resetting the curve is not the same gesture as turning the
  /// equalizer off, and a user mid-tuning who taps this almost certainly
  /// wants to keep adjusting, not lose the switch too.
  void resetCurve() {
    state = state.copyWith(
      preampDb: 0,
      gainsDb: List<double>.of(equalizerPresetCurves['Plano']!),
    );
    _schedule();
  }

  /// Applies whatever is pending right now. Called when the equalizer screen
  /// closes so the last drag before leaving is never dropped on the floor.
  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    await _apply();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(trackDelayDebounce, () {
      _debounce = null;
      _apply();
    });
  }

  Future<void> _apply() async {
    final settings = state;
    try {
      await ref.read(playbackEngineProvider).setAudioFilter(mpvAudioFilter(settings));
      final current = ref.read(settingsProvider);
      await ref.read(settingsProvider.notifier).set(current.copyWith(equalizer: settings));
    } catch (e) {
      // _schedule calls this from a Timer with nothing awaiting it, so a
      // throw from mpv or from the settings write would be an unhandled
      // async error in a zone with no handler. The state stays what the UI
      // is already showing — same policy as TrackDelayNotifier._apply.
      debugPrint('EqualizerNotifier._apply failed: $e');
    }
  }
}

final equalizerProvider =
    NotifierProvider<EqualizerNotifier, EqualizerSettings>(EqualizerNotifier.new);
