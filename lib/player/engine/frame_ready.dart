/// Maps mpv's video-width events to "the open media has a decoded frame".
///
/// The UI uses this to cover the shared texture's stale last frame across an
/// open. `vid=no` — how the video output is released before Android tears the
/// surface down, see `shouldReleaseVideoForBackground` — also nulls the width,
/// which is indistinguishable from "a fresh open has not decoded yet". Events
/// that arrive while the output is intentionally off are therefore DROPPED: the
/// cover belongs to the open sequence (PlayerScreen re-arms it explicitly on
/// every open), never to the `vid` property. Without this, returning from the
/// background could leave the black cover armed forever.
Stream<bool> frameReadyStream(
  Stream<int?> widthStream,
  bool Function() videoOutputEnabled,
) =>
    widthStream.where((_) => videoOutputEnabled()).map((w) => (w ?? 0) > 0);

/// Whether a just-reattached video output needs a nudge. mpv can fail to bring
/// its output back after the Android surface it held was destroyed, leaving a
/// black texture with no width ever reported. True → re-apply `vid=auto` and
/// force a frame.
bool shouldRetryVideoAttach({
  required bool enabled,
  required bool hasVideoSize,
}) =>
    enabled && !hasVideoSize;
