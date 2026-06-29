import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FlashNotifier extends Notifier<String?> {
  Timer? _t;
  @override String? build() { ref.onDispose(() => _t?.cancel()); return null; }
  void show(String msg) { state = msg; _t?.cancel(); _t = Timer(const Duration(milliseconds: 900), () => state = null); }
}

final flashProvider = NotifierProvider<FlashNotifier, String?>(FlashNotifier.new);
