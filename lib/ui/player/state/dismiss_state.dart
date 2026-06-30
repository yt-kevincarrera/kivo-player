import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ephemeral 0..1 dismiss progress driven by the swipe-down gesture.
/// 0 = fully on screen, 1 = fully dismissed.
final dismissProvider = StateProvider<double>((ref) => 0);
