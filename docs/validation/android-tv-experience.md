# Android TV experience

## Behavior

- Android's UI mode selects the TV experience before the app starts. Window
  width never selects TV mode. Phones retain `HomeShell` and their existing
  gestures, navigation, appearance and skip preferences.
- TV uses a landscape library with video artwork, horizontal shelves, a visible
  focus outline, search, USB storage and TV settings. Playback opens above the
  library and fills the display. Fit preserves the entire picture; Fill crops
  the edges; Stretch changes its proportions. None re-encodes the file.
- With player controls hidden, Left/Right seek by a separately persisted TV
  interval (default 3 seconds). A hold begins repeating after 450 ms, at 200 ms
  intervals. Optional acceleration changes the step to 3 times its base after
  2 seconds and 10 times after 4 seconds. Targets accumulate while the decoder
  catches up and remain within the known duration. Unknown duration never
  causes a seek to zero. Key-up, focus loss, video changes and app suspension
  stop the hold.
- Holding OK activates a control once, until release. A regression test first
  reproduced three activations from one key-down plus two repeat events; it
  now requires one. The same protection applies to shared Material controls
  inside the TV scope. Phone shortcuts retain their existing behavior.
- OK toggles playback with controls hidden. Up/Down reveal controls. Visible
  controls use directional focus and OK activation. Back closes a panel or
  hides controls before returning to the library. A touch gesture tutorial
  never covers TV playback.
- Audio tracks, subtitles, speed, chapter/bookmark tools, equalizer and other
  existing playback features remain reachable. TV opens shared feature panels
  in bounded dialogs. Queue editing exposes explicit play-next, move and
  remove controls. Time labels remain focusable and cycle through duration,
  time left and finish time.
- TV focus is visible even if an OEM reports the remote as a pointer. Labels,
  toggle states and current settings values are supplied to accessibility
  services. TV transitions respect reduced motion and layouts support larger
  system text.

## Mounted storage

`TvStorageBrowser` uses Android's mounted shared-storage volumes, rather than
requiring a document-picker application. Directory browsing and recursive
removable-video discovery execute on the existing I/O executor. All operations
are read-only and remain subject to Android storage permissions.

The native layer checks canonical paths against mounted roots, avoids symbolic
link recursion and private Android directories, and filters supported video
extensions. Mount/unmount broadcasts refresh TV sources. Permission and
disconnection states offer retry and access recovery inside Kivo.

Unindexed USB videos merge with MediaStore by the existing file identity, so
the same video appears once. Indexed metadata takes precedence. Losing a USB
drive does not discard indexed videos. TV resume entries remain visible when a
USB video's duration is not yet indexed. Phones do not use this extra scan.

The permission flow uses Kivo's existing storage permissions. A vendor may
still refuse access or omit the relevant settings activity; the UI explains
recovery instead of claiming that an empty directory is readable.

## Validation

- 794 local regression tests passed across large-screen navigation, player
  controls and features, home/library, settings, library services, settings
  persistence, Android media-indexer behavior and the app smoke test.
- The final focused TV run passed 37 checks. Coverage includes USB
  de-duplication, USB loss, independent phone behavior, unknown-duration resume,
  TV landscape entry, Back behavior, rapid taps, suspension during a hold,
  repeated-OK suppression, clearing search, and preserving concurrent preference updates.
- Directional UI checks cover reaching USB from the library, restoring focus
  on return, continuing to settings, folder navigation using only OK/Back,
  changing the seek interval without touching the screen, accessibility values
  and toggle state, and layouts at twice the text size.
- Targeted analysis of the changed application modules reported no issues.
- An Android debug build and a release build for `armeabi-v7a` compiled locally.
  The preview uses a command-line version override; the public release version
  and release workflows are unchanged.

The local screenshot harness can render synthetic media with real fonts:

```powershell
$env:KIVO_TV_FIXTURES = '<directory containing mountain.jpg, forest.jpg, coast.jpg, desert.jpg>'
$env:KIVO_TV_CAPTURE_DIR = '<existing output directory>'
$env:KIVO_TV_FONT_DIR = '<Flutter SDK>/bin/cache/artifacts/material_fonts'
flutter test --no-pub test/ui/large_screens/tv_experience_test.dart
```

Fixture images are optional, remain outside the repository, and are never
bundled into Kivo. UI tests also run without those environment variables.

## Preview artifact

The final local preview is `kivo-android-tv-preview-armeabi-v7a.apk`, version
`1.35.1-tv-preview`, package `dev.selector.kivo_player`, version code `3070`.
Only `armeabi-v7a` native libraries are packaged. APK signature verification
and ZIP alignment checks passed. Its certificate matches the APK read from the
installed TV app before updating it.

SHA-256: `3cc0a589680d3625e57490ac1f73331f81a2a7b753dacc50ad3faff96b0aa57f`.

The repository's public release version remains unchanged. No release tag or
public release was created. Temporary local signing configuration was removed
after the final build; the original signing material was preserved.

## Physical acceptance

A connected TV was inspected: Android 13, 1920 by 1080 pixels at 240 dpi, and a
32-bit ARM ABI. Its media-read permission was granted and all-files access was
unset. The connection intermittently entered ADB's `offline` state; that did
not establish that the TV was off. It later reconnected successfully.

After explicit owner approval, an initial signed preview was installed with an
in-place update. There was no uninstall or app-data clear. The new horizontal
library and its focus outline were observed on the TV, and the user's custom
accent color remained present. Directional key events reached the integrated
USB screen and its no-drive state.

A generated 180-second H.264/AAC fixture was copied to shared Movies storage
and indexed. Kivo discovered it, generated a thumbnail and opened its player.
Android's Kivo media session reported playing at position 30 seconds with
speed 1.0. A native video output reported 640 by 360 pixels. These observations
establish discovery and playback-engine activity, but do not establish stable
full-screen rendering, audible output or accurate physical remote seeking.

Other work was concurrently changing the TV's foreground application. The
owner therefore explicitly stopped further TV testing and requested code-only
completion. No more ADB actions were taken after that instruction. The final
APK contains subsequent search/preference fixes and was not reinstalled after
that stop; it shares the preview version string, so use the hash above to
identify the final artifact.

The owner confirmed that a USB drive was no longer available. Actual USB
reading, unplug/replug and permission recovery remain pending. The TV also
reported no handler for the two Android all-files-access settings intents;
the in-app recovery message was observed, not a successful special-permission
grant.

Remaining physical checks:

1. Install the final APK when the TV is available for exclusive testing.
2. Confirm Fit/Fill, stable video and audio, the configured tap, sustained seek,
   immediate stop on release, and Back behavior using the actual remote.
3. Connect a USB drive and exercise denied access, nested folders, playback and
   unplug/replug. Confirm resume, history, queue and track preferences.

The generated fixture remains at
`/sdcard/Movies/kivo-tv-qa-20261114-3483b43b.mp4` for later testing/cleanup.
No user media was edited or removed. Further device cleanup was also deferred
when the owner stopped TV actions.

Widget/fake-engine tests, media-session state and successful APK compilation
are separate evidence from full physical playback and storage acceptance.
