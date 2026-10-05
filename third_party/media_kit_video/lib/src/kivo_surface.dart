// Kivo patch (see KIVO_PATCHES.md).
import 'package:flutter/widgets.dart';

/// True while the Android render surface is being re-created (a new surface,
/// --vo re-initialised on it). Meanwhile the texture still shows the old
/// surface's last picture — usually the previous video — so an app covering
/// the video until its first frame should also wait for this to be false.
///
/// With Kivo's patch the surface is sized once to the screen and only grows,
/// so this is rarely true while a video starts.
final ValueNotifier<bool> kivoSurfaceBusy = ValueNotifier<bool>(false);

/// Kivo patch: a diagnostics hook (Kivo's open timeline). Null = silent.
void Function(String event)? kivoTrace;
