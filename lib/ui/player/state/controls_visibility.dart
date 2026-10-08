import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';

class ControlsVisibilityNotifier extends Notifier<bool> {
  Timer? _timer;
  bool _assistive = false;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    return false;
  }

  void show() {
    state = true;
    _restartTimer();
  }

  void hide() {
    _timer?.cancel();
    _timer = null;
    state = false;
  }

  void toggle() => state ? hide() : show();

  int _holds = 0;

  /// Something is under the user's finger (a queue card being dragged, its
  /// menu): show the controls and keep them up until every [hold] has been
  /// [release]d — fading the strip out mid-drag would drop the card.
  void hold() {
    _holds++;
    state = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Ends one [hold]; the last one restarts the auto-hide countdown.
  void release() {
    if (_holds == 0) return;
    _holds--;
    if (_holds == 0 && state) _restartTimer();
  }

  /// A screen reader (TalkBack) is on. Its user moves through the controls
  /// one by one, with no way to know they are about to fade: they stay up
  /// until hidden on purpose, and come up as soon as it turns on.
  ///
  /// Called on every player mount, not only on a change: this provider
  /// outlives the player, so a second video opened under TalkBack after the
  /// controls were hidden would otherwise start with them hidden.
  void setAssistive(bool on) {
    final was = _assistive;
    _assistive = on;
    if (on) {
      show();
    } else if (was && state) {
      _restartTimer();
    }
  }

  /// Whether a screen reader is driving the player (see [setAssistive]).
  bool get assistive => _assistive;

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (_assistive || _holds > 0) return;
    final ms = ref.read(settingsProvider).controlsAutoHideMs;
    _timer = Timer(Duration(milliseconds: ms), () => state = false);
  }
}

final controlsVisibleProvider =
    NotifierProvider<ControlsVisibilityNotifier, bool>(
      ControlsVisibilityNotifier.new,
    );

/// Whether the controls bar should be on screen at all.
///
/// The sync panel wins: it is what the user is looking at, and anything that
/// calls [ControlsVisibilityNotifier.show] — a stray tap on the video, the
/// seek bar, the queue strip — would otherwise punch the controls straight
/// through it. Gating the render rather than trusting every caller to check
/// is what makes that impossible instead of merely unlikely.
bool controlsShouldRender({
  required bool visible,
  required bool syncPanelOpen,
}) => visible && !syncPanelOpen;
