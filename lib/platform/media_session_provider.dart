import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'interfaces/media_session.dart';

/// Overridden in main() with the Android implementation.
final mediaSessionProvider = Provider<MediaSessionBridge>((ref) {
  throw UnimplementedError('mediaSessionProvider must be overridden');
});
