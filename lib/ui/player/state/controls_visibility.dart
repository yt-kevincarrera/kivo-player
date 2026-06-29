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
        ControlsVisibilityNotifier.new);
