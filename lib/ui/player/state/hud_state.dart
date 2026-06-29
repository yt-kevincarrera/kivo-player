import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum HudKind { brightness, volume, seek, speed }

class HudState {
  final HudKind kind;
  final double value;
  final String label;
  const HudState(this.kind, this.value, this.label);
}

class HudNotifier extends Notifier<HudState?> {
  Timer? _timer;

  @override
  HudState? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void show(HudKind kind, double value, String label) {
    state = HudState(kind, value, label);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 800), () => state = null);
  }

  void clear() {
    _timer?.cancel();
    state = null;
  }
}

final hudProvider = NotifierProvider<HudNotifier, HudState?>(HudNotifier.new);
