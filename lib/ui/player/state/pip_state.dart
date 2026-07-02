import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while the app is in an Android Picture-in-Picture window. Kivo hides
/// all its overlays while true so the window shows only the video.
final pipModeProvider = StateProvider<bool>((ref) => false);
