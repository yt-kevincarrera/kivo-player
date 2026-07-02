import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../player/open/video_source.dart';

/// The queued "next" session while the foreground countdown overlay is shown;
/// null when no autoplay is pending.
final autoplayPendingProvider = StateProvider<VideoSession?>((ref) => null);

/// Toggled true by the overlay when its 3s ring completes or the user taps
/// "Reproducir"; PlayerScreen listens, advances, and resets it to false.
final autoplayConfirmProvider = StateProvider<bool>((ref) => false);
