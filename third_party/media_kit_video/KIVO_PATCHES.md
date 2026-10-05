# Kivo's patches to media_kit_video 2.0.1

Vendored from pub.dev (`media_kit_video` 2.0.1, MIT — see `LICENSE`) and used
through `dependency_overrides` in Kivo's `pubspec.yaml`. Only the Android
video controller is changed; everything else is upstream as published.

## Why

On Android, whenever a video's size differs from the render surface's (the
first video of a session, and every change of resolution), media_kit:

1. resizes the `SurfaceProducer`, which hands mpv a new surface (`wid`);
2. in `widListener`, re-initialises `--vo` on it;
3. then `player.seek(player.state.position)`.

Step 3 is redundant while playing — changing `--vo` already makes mpv
re-create the video chain and refresh the stream at the current position
(`player/command.c`: `uninit_video_out` + `reinit_video_chain` +
`reselect_demux_stream(..., true)`). It flushed the audio (an audible gap)
and jumped back to `state.position`, which lags behind (a visible hop): the
"microsalto" Kivo users saw at the start of videos. And during steps 1–2 the
texture still shows the old surface's last picture — the previous video —
which flashed through once mpv's first frame had uncovered the video.

## What changed

`lib/src/video_controller/android_video_controller/real.dart`:

- `widListener`: no seek while playing. Paused, an exact seek to `time-pos`
  (the frame on screen) instead of the stale `state.position`, to redraw it.
- Publishes `kivoSettledSurfaceSize` (`lib/src/kivo_surface.dart`, exported
  from `media_kit_video.dart`) once the surface has settled at a size — after
  `widListener`, or straight away when no resize is needed. Kivo keeps its
  black cover over the video until this matches the video's size.

## Updating media_kit_video

Re-vendor the new version, re-apply the two changes above (search for
"Kivo patch"), and check whether upstream has fixed the seek on its own.
