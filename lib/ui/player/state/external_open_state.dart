import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../player/open/video_source.dart';

/// A video asked for from outside the player (a launcher shortcut or the
/// home-screen widget) while a PlayerScreen is up: that screen picks it up
/// and switches in place. Cleared once taken.
final externalOpenProvider = StateProvider<VideoSession?>((ref) => null);
