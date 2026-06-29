import 'package:flutter_riverpod/flutter_riverpod.dart';

class LockNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void lock() => state = true;
  void unlock() => state = false;
}

final lockProvider = NotifierProvider<LockNotifier, bool>(LockNotifier.new);
