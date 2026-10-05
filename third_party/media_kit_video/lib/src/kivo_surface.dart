// Kivo patch (see KIVO_PATCHES.md).
import 'package:flutter/widgets.dart';

/// The size of the Android surface mpv renders into, published only once a
/// resize has fully settled: the new surface exists AND mpv's video output
/// has been re-initialised on it.
///
/// While a resize is in flight the texture shows whatever the old surface
/// last held — usually the previous video — so an app covering the video
/// until its first frame should also wait for this to match the video's
/// size. `null` until the first surface has settled.
final ValueNotifier<Size?> kivoSettledSurfaceSize = ValueNotifier<Size?>(null);
