# Playback recovery and thumbnail resource fixes

## Scope and evidence boundary

The owner reported frozen video with advancing audio in Aida 11x36.avi, then
both streams stopping after a seek. Captured TV metadata identifies H.264
720x404/25 fps, MP3 audio and the Amlogic hardware AVC decoder. The exact file
is on the owner's USB drive, unavailable for this change. Only a 64 KiB header
sample and earlier runtime evidence are retained locally. The full episode
has not been replayed on the new code.

High-resolution playback/seek slowness was reported on the phone. No original
failing high-resolution file or phone performance trace is available. Synthetic
host coverage below is not an Android hardware benchmark or acceptance claim.
No TV commands or desktop UI automation were used for this change.

## Reproduction loops

Four deterministic failures were recorded before their respective fixes:

1. Native PreviewFrameSessionTest: prepare alone opened/warmed a thumbnail
   decoder before any frame was requested. The production handler was extracted
   behind its decoder factory seam while retaining that allocation behavior;
   the assertion expected zero allocations and observed one.
2. SeekBar widget test: releasing a drag committed one playback seek, then
   completing the in-flight preview started the queued second preview beside
   resumed playback. Expected one extraction, observed two; the cleared bubble
   could also be refilled by a late result.
3. DecoderController stream replay: a known-size video had already reported its
   first frame; video time then remained fixed while audio advanced. Automatic
   recovery never switched from hardware. This replays the reported symptom
   through the real controller, not the original AVI bitstream or OEM decoder.
4. A delayed-open test showed that old clock/frame readings during a new load
   could switch the new video's decoder before open completed. The final guard
   disables progress verdicts until that open completes and resets its baseline.

Commands:

```powershell
flutter test --no-pub test/ui/player/seek_bar_test.dart
flutter test --no-pub test/player/decoder/decoder_review_regressions_test.dart
# From android, using the Android Studio JBR:
./gradlew.bat :app:testDebugUnitTest --tests dev.selector.kivo_player.PreviewFrameSessionTest -x :app:compileFlutterBuildDebug --console=plain
```

Artifacts retain the red and green output outside the repository.

## Changes

- Preparing a thumbnail source records its path only. MediaMetadataRetriever
  is opened lazily for a requested frame; the discarded warm-up decode is gone.
  Switching videos and release still close the preceding native reader.
- Android 8.1/API 27 and newer uses getScaledFrameAtTime with a 240x240 bound.
  Android preserves aspect within those positive bounds, avoiding a full-size
  Java bitmap solely for subsequent downscaling. Codec reference buffers and
  the cost of decoding a source keyframe still exist.
- Older Android keeps its existing unscaled extraction fallback, then reduces
  the returned image. It benefits from lazy decoding, cancellation and prompt
  decoder cleanup; the full-size bitmap allocation remains an API limitation
  before Android 8.1. Previews and captures are not disabled by source size.
- Ending/cancelling a scrub discards queued preview targets and suppresses late
  results. The decoder is suspended on its serial native executor while the
  configured source remains available for later interactions. A running native
  decode cannot be interrupted safely; suspension follows it. Captures and
  mini-player artwork also release their decoder after extraction.
- Preview caches belong to the source path. A cached latest target supersedes
  obsolete pending work; changing source disposes the old controller.
- Android observes independent clocks every 500 ms through a separate libmpv
  client in a worker isolate. It shares the existing player/decoder and does
  not read media_kit's event queue. Optional monitoring does not block opening
  a file. Its client is detached before engine disposal.
- The progress watchdog notices fixed video time while audio advances by at
  least one second over the configured stall interval. One automatic hardware
  recovery switches to software and seeks in place, using the existing saved
  per-video preference, KV-504 report and undo action. Known dimensions and an
  earlier frame no longer permanently disable recovery of this pattern.
- Paused/seeking snapshots, disabled video output, audio-only files, unavailable
  clocks and explicit hardware/software choices do not trigger this recovery.
  A slow video whose timestamps still advance does not trigger it either.
  Concurrent startup/progress verdicts share a recovery guard. Later opens and
  disposal invalidate outstanding recovery work.

No extension-wide software default, imprecise keyframe jump, transcoding,
quality reduction or render-surface sizing change was introduced. The existing
first-surface workaround remains intact. Phone layout and TV navigation are
unchanged; the shared playback/resource fixes apply to both Android modes.

## Native probe compatibility

The first host probe failed because mpv 0.36 does not expose a video-pts
property. That failed implementation was corrected before packaging. The
shipped reader uses audio-pts and time-pos: mpv's play loop sets playback_pts
from video_pts while a non-sparse video is playing/draining, and switches to
audio time when video is no longer active. It does not infer real frame progress
from dimensions, a content hash, or estimated-frame-number.

Primary references:

- [mpv 0.36 playback clock selection](https://github.com/mpv-player/mpv/blob/v0.36.0/player/playloop.c)
- [mpv 0.36 properties and independent audio clock](https://github.com/mpv-player/mpv/blob/v0.36.0/player/command.c)
- [libmpv client ownership and thread safety](https://github.com/mpv-player/mpv/blob/v0.36.0/libmpv/client.h)
- [Android scaled frame extraction](https://developer.android.com/reference/android/media/MediaMetadataRetriever#getScaledFrameAtTime(long,%20int,%20int,%20int))

The checked-in headless harness can be repeated with a host libmpv and a locally
generated/static-image fixture containing both video and audio:

```powershell
dart run scripts/native/video_progress_probe.dart <libmpv-library> <fixture>
```

The host library is the media_kit Windows package's pinned 2023-09-24 build,
archive MD5 a832ef24b3a6ff97cd2560b5b9d04cd8. Static H.264/MP3 AVI 720x404 and
H.264/AAC MP4 3840x2160 fixtures both produced advancing timestamps and clean
observer shutdown with null outputs/software decoding. These verify the FFI
client and clock path; they do not reproduce the Amlogic hang or measure the
owner's phone. Physical surface-only freezes can evade a timestamp watchdog.

## Completed local checks

- 1,487 Flutter regression checks passed across player models, phone/TV player
  UI, home, settings, large-screen accessibility, core settings, Android indexing
  and smoke coverage.
- After the final in-flight-open guard, 64 decoder/probe checks passed.
- Eight native JVM checks passed after the final compatibility adjustment:
  three preview-session lifecycle cases, preview-size/aspect bounds and four
  existing mounted-storage merge cases.
- Targeted production analysis passed. The final in-flight-open guard also
  passed its own analysis check; git diff whitespace checks passed.
- Both real-libmpv host probe fixtures passed. The 4K fixture's picture clock
  advanced from 200 ms to 2700 ms during the captured run. This is compatibility
  evidence with software/null outputs, not a phone speed measurement.
- No public tag/release or CI run is part of this private preview.

## Signed artifacts

Preview 7 is `1.35.1-tv-preview.7`, with Android version codes 3076 (armeabi-v7a)
and 4076 (arm64-v8a). Both signatures and 16 KiB ZIP alignment checks passed;
JNI contents include the matching ABI, libmpv, JNI helper, Flutter and app code.
Certificate SHA-256 matches the installed preview 6:
`8e7ae56aa5b6b4aab8206ce27fb7c0d27e5e5b098653b892d8d2ff395c3451dd`.

- `kivo-playback-preview7-armeabi-v7a.apk` SHA-256: `4d2d815ef19c863bc5bc0d75c69ea3596c3b607a7d9ec17f8255e7cc0cf58eea`
- `kivo-playback-preview7-arm64-v8a.apk` SHA-256: `be61f6adcd8c71345cec3271193c4ffd47a16e152e4806fe0ca30f24740e468a`

APKs, verification logs, fixture files and metadata remain outside Git. Neither
APK was installed: the TV was unavailable throughout. Packaging initially hit
a host JVM native-memory failure with the project's 8 GiB heap configuration;
the final build passed with an invocation-scoped 2 GiB heap and two workers.
No persistent Gradle settings or public version/release configuration changed.

## Acceptance still required

- Replay the original episode at the failing timestamp with preview 7; check
  image/audio movement, automatic recovery/undo and seeks in both directions.
- Repeatedly seek the original high-resolution phone file; measure first-frame
  recovery and stable playback with actual hardware decoder/profile/bit depth.
- Check TV/phone lifecycle changes, source switches, background audio, resumed
  playback, queue advances and the first-surface compatibility workaround.

A successful local regression or signed build does not close these checks.
The OEM decoder/root cause and original high-resolution timing remain unproven.
