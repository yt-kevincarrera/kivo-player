import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/pip_controller.dart';

/// Overridden in main() with the Android implementation.
final pipControllerProvider = Provider<PipController>((ref) {
  throw UnimplementedError('pipControllerProvider must be overridden');
});

/// Whether the device supports picture-in-picture. Shared by the player's top
/// bar and the gesture map — both hide PiP when it is unavailable.
final pipSupportedProvider =
    FutureProvider<bool>((ref) => ref.read(pipControllerProvider).isSupported());
