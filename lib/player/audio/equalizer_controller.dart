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

  /// True from the moment a mutator changes [state] until a matching
  /// [_apply] write lands with nothing newer pending. While true, the
  /// [ref.listen] callback below ignores whatever [settingsProvider]
  /// reports — otherwise the settings write this notifier's own [_apply]
  /// makes (after a real `await` on the mpv round trip) would land mid-drag
  /// and reset [state] back to a stale value, silently eating whatever the
  /// user did in between.
  bool _dirty = false;

  @override
  EqualizerSettings build() {
    ref.onDispose(() => _debounce?.cancel());
    // `listen`, not `watch`: this notifier writes settingsProvider.equalizer
    // itself (in [_apply]), so `ref.watch`ing it here would invalidate this
    // very provider on every one of its own writes — and invalidateSelf runs
    // this build's onDispose callbacks immediately (see
    // ProviderElement.invalidateSelf in riverpod/framework/element.dart),
    // canceling [_debounce] out from under any edit made in the meantime.
    // Compare `track_delay_controller.dart`'s [TrackDelayNotifier], which
    // sidesteps all this by watching a provider it never writes to; this one
    // can't do that (it needs to pick up an external reset of the very same
    // field), so it reacts via `listen` instead — that never invalidates or
    // rebuilds this provider, so [_debounce] survives every self-write.
    ref.listen(settingsProvider.select((s) => s.equalizer), (_, next) {
      // A genuine external change (the "Restablecer valores" tile) lands
      // here and is adopted as long as nothing local is pending. While
      // dirty, this is either an echo of this notifier's own write (already
      // reflected in state) or a change that arrived mid-drag — both must
      // be ignored so the newer local value isn't stomped.
      if (!_dirty) state = next;
    });
    return ref.read(settingsProvider).equalizer;
  }

  void _mutate(EqualizerSettings next) {
    state = next;
    _dirty = true;
    _schedule();
  }

  void setEnabled(bool enabled) => _mutate(state.copyWith(enabled: enabled));

  void setBand(int index, double db) => _mutate(state.withBand(index, db));

  void setPreamp(double db) =>
      _mutate(state.copyWith(preampDb: clampEqualizerDb(db)));

  void applyPreset(String name) {
    final curve = equalizerPresetCurves[name];
    if (curve == null) return;
    _mutate(state.copyWith(gainsDb: List<double>.of(curve)));
  }

  /// Back to a flat curve and zero preamp. Leaves [EqualizerSettings.enabled]
  /// untouched — resetting the curve is not the same gesture as turning the
  /// equalizer off, and a user mid-tuning who taps this almost certainly
  /// wants to keep adjusting, not lose the switch too.
  void resetCurve() => _mutate(state.copyWith(
        preampDb: 0,
        gainsDb: List<double>.of(equalizerPresetCurves['Plano']!),
      ));

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
      // Only clear dirty if nothing newer landed while the two awaits above
      // were in flight — if it did, state has already moved on to that
      // newer value, a fresh debounce is already scheduled for it, and this
      // notifier must keep ignoring settingsProvider until that one lands.
      if (state == settings) _dirty = false;
    } catch (e) {
      // _schedule calls this from a Timer with nothing awaiting it, so a
      // throw from mpv or from the settings write would be an unhandled
      // async error in a zone with no handler. The state stays what the UI
      // is already showing — same policy as TrackDelayNotifier._apply.
      // _dirty stays true: the write never landed, so this local state is
      // still the only place holding the user's intent.
      debugPrint('EqualizerNotifier._apply failed: $e');
    }
  }
}

final equalizerProvider =
    NotifierProvider<EqualizerNotifier, EqualizerSettings>(EqualizerNotifier.new);
