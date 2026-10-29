# Kivo Android native libraries

This is the Android plugin from `media_kit_libs_android_video` 1.3.8 (MIT).
The Java bridge and `libmediakitandroidhelper.so` are unchanged. The bundled
`libmpv.so` is rebuilt from the same upstream source revision with six extra
FFmpeg decoders: `rv10`, `rv20`, `rv30`, `rv40`, `cook`, and `sipr`.

The upstream small build already enables the RealMedia demuxer and several
RealAudio decoders, but omits these decoders. Both video and audio support are
needed: a RealVideo/Cook file otherwise ends with no playable streams.

## Normal app builds

The app uses the four checked-in `native/realmedia-*.jar` files. Gradle verifies
their SHA-256 digests against `native/manifest.json` before building. No native
source compilation or native binary download runs during a normal Flutter build.

Keep all four ABIs (`arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`), including the
unchanged JNI helper for each ABI. Do not substitute a stock archive: it loses
RealMedia support. The app's normal release pipeline still produces three APKs.

Run `python3 scripts/native/verify.py` from the repository root to verify archive
contents, hashes and 16 KB ELF page alignment. On Windows use `py -3` in place of
`python3`.

## Rebuilding the native libraries

Use Linux or WSL, Python 3.10+, Android NDK r25c, Meson 1.3.2, and the host tools
listed in `.github/workflows/native-libraries.yml`. That manually triggered
workflow rebuilds and uploads artifacts without publishing a release.

`scripts/native/sources.lock.json` pins every source revision and archive hash.
`toolchain.lock.json` identifies the NDK download and Google's SHA-1 checksum.
`base-artifacts.lock.json` pins the original archives used to preserve the JNI
helper. The existing upstream mpv/FFmpeg patches and build options are retained.
The `--disable-gpl`, `--disable-nonfree` and `-Dgpl=false` options are unchanged.

```bash
# Keep the build directory persistent: WSL startup may clean /tmp.
export KIVO_NATIVE_WORK="$HOME/.cache/kivo-native-realmedia-v1"
export ANDROID_NDK_HOME=/path/to/android-ndk-r25c
export KIVO_NATIVE_JOBS=4
bash scripts/native/build.sh
python3 scripts/native/package.py \
  --work "$KIVO_NATIVE_WORK" \
  --base-cache "$HOME/.cache/kivo-native-jni"
python3 scripts/native/verify.py
```

The build saves unstripped libraries in `$KIVO_NATIVE_WORK/symbols` and packages
stripped libraries with fixed ZIP entry dates. Use a new work directory when the
source lock or preparation recipe changes. Review the generated manifest and
native playback results whenever replacing artifacts. This recipe pins sources
and tools; it does not promise bit-identical results across arbitrary host tools.

## Regression validation

`scripts/native/smoke.c` loads the actual Android `libmpv.so` through its public
C API, uses software decoding with null audio/video outputs, and checks decoded
video dimensions, audio parameters, duration, playback progress and seeking.
`fixtures.lock.json` records public FFmpeg samples and their hashes; samples are
downloaded only for testing and are not distributed in the app.

The Android media-catalog instrumentation test covers `.rm` misclassified as
audio, `.rmvb` with an application MIME type, video-row deduplication, and
exclusion of ordinary audio files. The Flutter regression covers the asynchronous
terminal error that otherwise leaves a black screen without an error message.

Android may hide RealMedia rows classified as audio/data under scoped storage.
The catalog includes accessible rows, including those available through Kivo's
existing all-files access setting. **Open file** also works without requesting
an additional media permission. No `READ_MEDIA_AUDIO` permission is added.

Native headless decoding is separate evidence from Flutter surface rendering,
audible output, and playback on the reporter's Xiaomi. Keep those distinctions
in the validation report.

## Local validation (2026-10-29)

- All four native archives pass SHA-256, ELF ABI, archive-content and 16 KB
  alignment checks.
- On the Android 37 x86_64 emulator (16 KB pages), the native C API test passes
  all six decoder checks, decoded video/audio parameters, positive duration,
  playback progress and a paused seek for RV10/SIPR, RV20/SIPR, RV30/Cook and
  RV40/Cook. Generated H.264/AAC MP4 and MPEG-4/MP3 MKV regressions also pass.
- The RV20/SIPR sample has frames at 0, 0.792, 1.584, 2.376 seconds, etc.
  Seeking to 2 seconds correctly shows the first available frame at 2.376.
- `MediaCatalogInstrumentedTest` passes against Android's actual MediaStore.
- The affected Flutter suites pass 133 tests, including optional preview
  failures and recovery to a supported format. Debug app/test APKs build.
- Flutter surface playback remains inconclusive on this emulator: the new
  library and a control APK containing the original stock x86_64 library both
  show a black H.264 video surface and report `EGL_BAD_ATTRIBUTE` in GFXSTREAM.
  This reproduces with software and host emulator graphics. It is not evidence
  that the rebuilt library renders correctly on a physical device.
- The original reporter's file and physical Xiaomi remain unverified. The
  headless C test uses null audio/video outputs and does not prove audible
  output or Flutter surface rendering.

Compressed native archive sizes (these are not full APK sizes):

| ABI | Stock bytes | Kivo bytes | Increase |
| --- | ---: | ---: | ---: |
| arm64-v8a | 5,729,978 | 5,793,638 | 63,660 |
| armeabi-v7a | 5,499,353 | 5,565,936 | 66,583 |
| x86_64 | 6,516,632 | 6,567,439 | 50,807 |
| x86 | 5,839,220 | 5,895,925 | 56,705 |
