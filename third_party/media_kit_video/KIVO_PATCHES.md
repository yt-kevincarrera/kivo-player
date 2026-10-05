# Kivo's patches to media_kit_video 2.0.1

Vendored from pub.dev (`media_kit_video` 2.0.1, MIT — see `LICENSE`) and used
through `dependency_overrides` in Kivo's `pubspec.yaml`. Only the Android
video controller is changed (plus `lib/src/kivo_surface.dart`, exported from
`media_kit_video.dart`); everything else is upstream as published.

## Why

Upstream re-sizes the Android render surface to every video's exact size.
Each resize hands mpv a new surface (`wid`), and `widListener` re-creates
`--vo` on it and then seeks to `player.state.position`. Measured on a Pixel 6
with Kivo's open timeline (problem report → "Recent video opens"):

- 130–185 ms per resize of black screen, on top of mpv's own first frame
  (a 426x240 video was decoded at +80 ms and shown at +359 ms);
- a stream refresh while playing (the video hitches, the audio is held);
- the seek flushed the audio and jumped back to a stale position;
- meanwhile the texture shows the old surface's last picture — the previous
  video.

## What changed (`lib/src/video_controller/android_video_controller/real.dart`)

**History.** Kivo 1.26.4 shipped the fixed surface below and showed a
single stretched pixel instead of the video on a Pixel 6: Android re-created
the surface at another size than the one asked for, and mpv drew a full
frame into a tiny buffer. `_kivoReassert` now asks for the size again
whenever a new surface comes back at another size (confirmed working on the
Pixel 6 in 1.26.5), and the native size of every surface is traced.

**Default since Kivo 1.26.6: the fixed surface** (`kivoFixedSurface == true`).
Kivo's "Dibujo de video clásico" setting turns it off: the surface then
follows each video's size, as upstream. Common to both: no seek while
playing, `rect` = the video, `kivoSurfaceBusy`, `kivoTrace`.

The fixed surface:

- **The surface is not re-sized per video.** It starts at 16:9 of the
  DISPLAY's short side (1920x1080 on a 1080-wide screen, so 16:9 video maps
  1:1) — sized at creation, before any video — and only grows, never
  shrinks, when a video will be shown bigger than it on this display
  (fitted in the orientation that suits it, never beyond its own pixels):
  in practice once, for the first portrait video. The display, not the
  window, so PiP / split-screen never shrink it.
- **mpv stretches every video over the whole surface** (`keepaspect=no`), and
  `rect` always carries the VIDEO's size — set as soon as the size is known,
  and kept over the native `VideoOutput.Resize` (which upstream sets to the
  surface size) — so Flutter lays the texture out at the video's aspect
  ratio and undoes the stretch. Kivo's aspect modes are `BoxFit`s on that.
- **Subtitles mpv draws (PGS, ASS)** are blended into the video
  (`blend-subtitles=video`) only when the video is stretched (its shape is
  not the surface's); otherwise they are drawn normally, sharp.
- `widListener` uses the surface's size for `android-surface-size`, and no
  longer seeks while playing (re-setting `--vo` already refreshes the stream;
  mpv `player/command.c`); paused, it seeks exactly to `time-pos`.
- `kivoSurfaceBusy` (`lib/src/kivo_surface.dart`) is true while a surface is
  being re-created; Kivo keeps its black cover over the video meanwhile. It
  is cleared by `widListener`, or after 500 ms only if no new surface came.
  `kivoTrace` is a diagnostics hook for Kivo's open timeline.

The package's SDK constraint predates Dart 3: no records in the patch.

## Updating media_kit_video

Re-vendor the new version, re-apply the changes above (search for
"Kivo patch"), and check whether upstream has changed how it sizes the
surface.
