import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set to the queue index the user tapped in the strip; PlayerScreen listens,
/// jumps to it (reusing the open flow, not counted as autoplay), then clears.
final queueJumpProvider = StateProvider<int?>((ref) => null);
