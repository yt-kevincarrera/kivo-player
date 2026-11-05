# AVI support investigation (2026-11-05)

Base revision: `161e981`. The working tree adds AVI library thumbnail fallback,
Cinepak decoding and native AVI audio-clock recovery. The final four-ABI bundle
is included in the working tree and passes source/hash/ELF verification. On a physical Pixel 6
(ARM64, Android 17 / API 37), the updated library passes 79 native checks across
eleven AVI files and two other-container controls, plus 16 checks at 1.5x.
No release has been published. These are software-decoder tests, separate from
Flutter surface rendering, audible output and the reporter's original file.

## Native recovery implementation

`scripts/native/patches/mpv-avi-audio-clock.patch` marks audio streams from the
actual AVI demuxer, regardless of filename or content URI. Its decoder wrapper
covers forward holes with PCM silence in blocks of at most 8192 samples and
keeps the later valid audio at its original timestamp. A backwards timestamp
reset is normalized without dropping decoded samples. Explicit seeks reset
the correction and release any pending frame. The repair interval is limited
to 30 seconds; larger malformed gaps retain upstream behavior.

The production timing functions are shared with the standalone
`test/native/avi_audio_clock_test.c` test. It covers a healthy timeline, the
observed leading AC-3 gap, a forward MP3 timestamp jump, consecutive backwards
resets, a real user seek backwards, rounding and allocation bounds. It passes
with `-Wall -Wextra -Werror`.

The app's position stream and seek bar remain unchanged: the correction is in
the decoder timeline. The exact reporter file that repeatedly returns the bar
to zero is unavailable. The public sync sample reproduces an internal audio
timestamp reset, but has not reproduced that exact repeated UI symptom.

`scripts/native/recipe.json` adds Cinepak alongside the six existing RealMedia
decoders. The preparation signature now covers that recipe, the timing header
and downstream patches. Packaging rejects stale prepared sources and records
the recipe and patch hashes in the bundle manifest.

## Reproduced defect and fix

`AndroidMediaIndexer` only used the bundled decoder when Android failed to
generate a RealMedia thumbnail. AVI files had no such fallback, although Kivo's
decoder can read video streams Android's thumbnail service cannot handle.

The regression initially failed for both an empty native thumbnail and a native
exception: expected the injected decoder image `[5]`, received `null`. The fix
uses the existing serial software thumbnailer for `.avi` as well as `.rm` and
`.rmvb`, preserving the original content URI. Native images still take priority;
the cache stays bounded, retries failures and invalidates modified files.

```powershell
flutter test --no-pub test/platform/android_media_indexer_realmedia_test.dart test/platform/android_media_indexer_failure_test.dart test/platform/media_kit_thumbnailer_test.dart
flutter analyze --no-pub lib/platform/android/android_media_indexer.dart test/platform/android_media_indexer_realmedia_test.dart test/platform/android_media_indexer_failure_test.dart
git diff --check
```

Result: 18 tests pass; analysis reports no issues. These are host regression
tests at the method-channel/decoder seam, not Android thumbnail rendering proof.

## Initial playback investigation

Generated eight-second synthetic AVI files with MPEG-4/MP3 (B-frames),
MS MPEG-4 v3/MP3, Xvid/MP3 and MJPEG/PCM. Local diagnostic artifacts remain under
the ignored `build/avi-diagnosis/` directory. An adapted copy of the existing
native smoke harness measures media-time progress against a monotonic clock
over three seconds; the acceptable ratio is 0.85 to 1.15.

Ran the actual checked-in x86_64 `libmpv.so` (mpv 0.36.0) on the Pixel_10 Android
17 emulator with null audio/video outputs and software decoding. The first
MJPEG/PCM AVI run decoded video/audio but progressed at 0.433x. On repetition,
the same AVI progressed at 1.005x and its losslessly remuxed MKV control at
1.000x. The slow result was therefore not stable. The emulator was still in
boot animation, and host free physical memory was about 647 MB of 16 GB.

Stopped this emulator after the control run to release resources. The remaining
AVI codec checks, native screenshots and seeking were not completed. A separate
MPEG-4/MP3 MKV remux failed because of missing packet timestamps and is excluded
from all conclusions. Null outputs do not establish Flutter surface rendering,
audible output or behavior on the reporter's phone.

## Expanded public AVI coverage

The follow-up no longer depends on obtaining the reporter's file to investigate
compatibility. `scripts/native/avi_smoke.py` tests seven SHA-256-pinned public
[FFmpeg samples](https://samples.ffmpeg.org/archive/extension/avi/) and can
generate four additional AVI codec combinations. It compiles `smoke.c` against
the local Android NDK and loads the actual checked-in `libmpv.so` in Android.
Public samples are downloaded for testing only; they are not bundled in Kivo.

```powershell
py -3 scripts/native/avi_smoke.py --adb C:/Users/carre/AppData/Local/Android/Sdk/platform-tools/adb.exe --ndk C:/Users/carre/AppData/Local/Android/Sdk/ndk/28.2.13676358 --serial emulator-5560 --jar third_party/media_kit_libs_android_video/native/realmedia-x86_64.jar --generate --work build/avi-smoke-final
```

The runner requires Android to finish booting. Each sample checks decoded video
and audio, a paused exact seek to two seconds, raw thumbnail pixels, and two
three-second timing windows. Timing requires media progress at 0.85 to 1.15 of
wall time and final reported A/V skew within 250 ms. The runner records failures,
sample hashes and native logs rather than stopping at the first bad file. A
baseline exited nonzero for the compatibility defects described below; the
updated library must exit zero. This is a focused smoke test, not full-length
playback acceptance.

Both complete runs performed 45 checks: 37 passed and 8 failed. Eight of
the eleven samples met all measured assertions; three had compatibility faults.
Passing timing assertions does not mean a damaged audio track is error-free:
the public `mpeg4-slow-mp3.avi` sample still logs MP3 header/decoding errors.
The full second run, file hashes, differential experiments and recovery-option
results are preserved in [the native result artifact](validation/avi-native-2026-11-05.json).

| Sample | Actual video/audio | Observed behavior |
| --- | --- | --- |
| Public QPel/B-frame sample | MPEG-4 ASP / MP3 | Decode, seek, thumbnail and timing pass; recoverable timestamp warnings |
| Public slow-MP3 sample | MPEG-4 ASP / MP3 | Assertions pass; invalid MP3 headers and audio errors remain |
| Public sync sample | MPEG-4 ASP / MP3 | Intermittent seek/timing failure; audio PTS jumps from 0.024 to 13.008 s |
| Public AC-3 sample | MPEG-4 ASP / AC-3 | Decode, seek and thumbnail pass; repeated slow progress around 0.55x and A/V skew |
| Public Xvid/AAC sample | MPEG-4 ASP / AAC | All assertions pass |
| Public camera sample | MJPEG / unsigned 8-bit PCM | All assertions pass |
| Public legacy Cinepak sample | Cinepak / signed 16-bit PCM | Decoder initialization fails; Cinepak absent from the native decoder list |
| Four generated samples | MPEG-4/MP3, MS MPEG-4 v3/MP3, Xvid/MP3, MJPEG/PCM | All assertions pass |

## Differential diagnosis

The AC-3 case reproduced on repeated runs of the same native library. These
experiments change one input or option at a time:

- Disable audio in the original sample: normal video progress at 0.992x.
- Generate a clean MPEG-4 AVI with six-channel AC-3: normal progress at 0.998x.
- Repack the original streams into a fresh eight-second AVI without re-encoding:
  progress improves to 0.971x, but an audio error and a desync warning remain.
- Repack into MKV without re-encoding: still slow at 0.594x.
- Disable OpenDML indexing or force stereo: original remains slow.
- Ignore audio errors, request corrupt-frame output, discard corrupt packets,
  increase analysis time, or generate PTS/ignore DTS: none fixes the original.

The desktop FFmpeg 8 reference also rejects an AC-3 packet with `Invalid data
found when processing input`. The evidence points to the handling of invalid
audio packets/timestamps in this file; it does not establish a general AC-3
decoder failure or the cause on the reporter's phone. No global timing,
decoder-selection or error-concealment setting was changed in the app.

The Cinepak failure is independently reproducible. Desktop FFmpeg decodes that
sample, while Kivo's Android decoder list lacks Cinepak. Supporting this codec
requires rebuilding the bundled native libraries; the thumbnail fallback alone
cannot supply a missing decoder.

The existing RealMedia decoder presence checks and a raw thumbnail from
`android/app/src/androidTest/assets/generated.rm` still pass with the extended
native harness.

## Baseline delivery boundaries

The test uses the x86_64 Android 17 emulator with null audio/video outputs and
software decoding. It does not establish audible output, Flutter surface
rendering, ARM hardware decoding, full-length playback, or the reporter's exact
failure. The host was under memory pressure; passing controls and repeated
audio-specific failures help distinguish cases, but are not phone performance
acceptance. The emulator was closed after testing.
The last generated MJPEG timing run reported 52 dropped frames despite meeting
the media-progress and final-skew thresholds. These assertions do not certify
smooth frame presentation; recorded drop counts and warning messages must be
reviewed alongside the pass/fail flags.

## Updated bundle verification

The final `avi-v2` libraries were rebuilt with the pinned NDK r25c and source
revisions for all four ABIs. Their hashes, ELF architectures, archive contents
and 16 KB alignment pass verification. Each JNI helper is byte-identical to its
previous bundled version. Compressed archive increases over the previous Kivo
bundle are 2628 bytes (ARM64), 1952 bytes (ARMv7), 3318 bytes (x86_64) and
2834 bytes (x86).

The [updated native result artifact](validation/avi-fixed-2026-11-05.json)
retains the individual assertions, sample/library hashes, timings and warnings.
The connected physical Pixel 6 was used only through temporary native test
directories. Kivo was not installed, uninstalled or opened on it, and no personal
media or app data was accessed.

| Validation | Result |
| --- | --- |
| Main matrix: seven public and four generated AVIs, H.264/AAC MP4 and MPEG-4/MP3 MKV controls | 79/79 checks pass |
| Three previously failing public AVIs at requested speed 1.5x | 16/16 checks pass |
| RealMedia decoder presence, four public RealMedia samples and two controls | 13/13 checks pass |
| PCM comparison: healthy audio unchanged, damaged gaps silent and valid audio retained | 7/7 assertions pass |
| Standalone production clock helpers, repeated resets, seeks and allocation limits | Pass |
| Affected Flutter platform, decoder, control, open and A/B-loop regressions | 174 assertions pass after rerunning one infrastructure failure |
| Targeted Dart analysis | No issues |
| Debug APK integration, bundled native bytes, 16 KB ZIP alignment and debug v2 signature | Pass |

The common 45 assertions from the original matrix now all pass on ARM64. The
baseline used an x86_64 emulator; these counts are compatibility evidence, not a
cross-device performance benchmark. All recorded real-time/timeline windows in
the new physical-device runs report zero dropped frames. Null outputs still do
not certify smooth frame presentation.

The damaged AC-3 sample advances at 0.996–0.997x in its repeated three-second
windows and 0.999x over eight seconds. The sync sample advances at 0.995–0.996x
and 0.998x respectively. Both detailed timelines report zero backwards jumps
and zero resets to the start; their maximum native A/V-clock skew is 3 ms and
1 ms. Genuine backwards seeks and subsequent playback pass. The 1.5x run also
preserves the requested playback speed.

PCM output from a healthy generated AVI is byte-identical before and after the
patch. All 1,532,928 baseline stereo PCM frames from the damaged AC-3 sample are
retained in order, with only zero-valued samples inserted into timestamp holes.
An initial test incorrectly assumed all inserted silence was at the beginning;
its failed result is retained locally. Inspecting the PCM found a second silent
hole near the end. The final assertion checks every original sample in order
and permits only inserted silence, including inside the track. Negative controls
confirm it rejects dropped or changed samples.

The first broad Flutter invocation passed 135 assertions but could not load
`gesture_math_test.dart` because the tester WebSocket handshake failed. Running
that file alone with concurrency 1 passes all 39 assertions. No product
assertion failed; the initial infrastructure failure remains in the evidence.

`flutter build apk --debug --target-platform android-arm64 --no-pub` succeeds.
The generated APK includes ARM64, ARMv7 and x86_64 native libraries; all included
`libmpv.so` and JNI helper bytes match the corresponding validated bundle
archives exactly. Android `zipalign -c -P 16 4` and debug APK v2 signature
verification pass. The debug artifact is not a published, update-safe release
and was not installed on the phone. The six identified native test directories
were removed after pulling their results; other existing directories were left
untouched. CI has not run remotely because this work has not been pushed.

Some damaged public files still log invalid compressed packets or malformed
video timestamps. Silence covers reported timestamp holes; it cannot recreate
missing sound or establish semantic lip-sync. Gaps over 30 seconds retain
upstream behavior. The reporter's exact repeated seek-bar-to-zero symptom is
not reproduced in Flutter and remains a specific acceptance boundary.
