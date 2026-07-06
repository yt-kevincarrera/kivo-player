import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True once the CURRENTLY-open media has produced its first decoded video
/// frame. False while a (re)open is in flight — the media_kit texture is a
/// process-lifetime singleton that keeps painting the PREVIOUS video's last
/// frame until the new media decodes, so the player covers it with black while
/// this is false to avoid flashing the stale frame. Seeded per open in
/// `PlayerScreen._openSession` (true when expanding the same session, whose
/// frame is already correct; false for a fresh open) and driven by the engine's
/// `hasVideoFrameStream` (media_kit resets width→null on every open, then sets
/// it when the first frame is ready).
final videoFrameReadyProvider = StateProvider<bool>((ref) => false);
