import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';

class ControlsVisibilityNotifier extends Notifier<bool> {
  Timer? _timer;

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

  void _restartTimer() {
    _timer?.cancel();
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
