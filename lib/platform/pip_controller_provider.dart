import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/pip_controller.dart';

/// Overridden in main() with the Android implementation.
final pipControllerProvider = Provider<PipController>((ref) {
  throw UnimplementedError('pipControllerProvider must be overridden');
});
