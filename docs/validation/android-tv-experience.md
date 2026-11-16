# Android TV experience

## Current behavior

Android UI mode selects the TV experience; window width does not. Phones keep
HomeShell, their presentation, touch gestures and skip preferences. TV has its
own dark theme, landscape navigation, artwork-led home and complete library.

The default TV source is the set of currently mounted removable drives. Their
videos appear in the ordinary library, not a USB menu or a file-browser home.
No drive produces an inline connection/retry state. Internal indexed files are
not substituted for the disconnected drive. Mount events and foreground return
refresh sources without switching the current library view.

The TV library keeps search, watched/in-progress/completed filters, all seven
video sort orders, folders, playlists, resume state and per-video actions. Lists
use the existing store and playback model, with explicit move/remove actions
instead of drag gestures. No media are copied, renamed or deleted by discovery.

TV settings have large remote controls throughout nested sections. Shared
setting models retain the phone renderers; TV renders choices as side panels,
numeric values as left/right editors, and switches as whole-row actions. This
includes nullable language choices, equalizer bands, end actions, colors and
subtitle styling. Full-screen sections use the same TV page header and Back.

The player keeps the editable queue strip, tracks, subtitle appearance,
synchronization, speed, chapters, bookmarks, sleep timer, equalizer, decoder
choices, end actions and other existing tools. Fit preserves the entire image,
Fill crops, and Stretch changes proportions. None re-encodes the source.

## Remote and focus behavior

- Hidden controls: Left/Right seek by a separate TV preference (3 seconds by
  default), OK toggles playback, and Up/Down reveal controls.
- A held seek starts repeating after 450 ms, then every 200 ms. Optional
  acceleration multiplies the step after 2 and 4 seconds. Key-up, focus loss,
  suspension and a different video stop the hold. Unknown duration does not
  send a seek to zero.
- Visible controls: arrows navigate and OK activates. The playback action row
  has an explicit stable order and scrolls horizontally rather than wrapping.
  Audio, Subtitles and More remain reachable at large text sizes. Right at the
  last action keeps a visible focus target; Left returns through the row.
- Panels keep focus within their route. A selected choice receives initial
  focus; otherwise Back supplies a visible fallback. Return focus is restored
  after the outgoing route completes, to the control that opened it.
- Pointer-shaped remotes and accessibility activation establish the same
  return target as the D-pad. Focus uses an explicit contrasting outline.
- Held OK activates only once. Controls stay visible while a panel is open.
  Back dismisses a panel, then hides controls, then returns to the library.
- Focus labels, current values and toggle states are exposed to accessibility.
  Reduced motion and twice-normal text size are covered locally.

## Storage access

TvStorageBrowser reads Android mounted shared-storage roots on the I/O
executor. Canonical root checks, supported video extensions, hidden/private
folder filtering, symlink avoidance and path de-duplication remain in place.
Indexed metadata takes precedence when a direct and a MediaStore entry refer
to the same file. The extra removable scan applies only to TV.

Android may grant READ_MEDIA_VIDEO while still hiding unindexed files from a
FUSE directory listing. The TV library asks MediaScannerConnection to index a
newly encountered mounted root, then refreshes the ordinary index. Explicit
Refresh retries scanning. It never grants permissions through ADB or claims
that filtered empty directory output proves the directory contains no videos.

The tested OEM omits both Android all-files-access settings activities. The
permission flow distinguishes that condition from a granted media-read
permission, instead of sending the owner to an unrelated permission switch.

## Local verification

The original focus regression first failed at More: its rectangle was on a
second wrapped row, unreachable by continuing Right. The corrected test
reaches Audio, Subtitles and More and returns Left, with both standard and
large text. A full PlayerScreen check covers menu open/Back/restore as well.

Additional focused checks exercise mounted-source boundaries and decoded file
URIs, connection events, no-drive behavior, search reset, phone-shell isolation,
nullable language reset, equalizer edits and end-action exclusions, plus list
creation/addition/reordering through the TV presentation. Native storage merge
and extension coverage use TvStorageFilesTest.

The screenshot harness renders the actual Flutter widgets with optional local
fixture media and real fonts:

```powershell
$env:KIVO_TV_FIXTURES = '<mountain.jpg, forest.jpg, coast.jpg, desert.jpg directory>'
$env:KIVO_TV_CAPTURE_DIR = '<existing output directory>'
$env:KIVO_TV_FONT_DIR = '<Flutter SDK>/bin/cache/artifacts/material_fonts'
flutter test --no-pub test/ui/large_screens/tv_experience_test.dart test/ui/large_screens/tv_playback_menus_test.dart
```

Fixtures and captures remain outside the repository and APK. Test images,
synthetic playback and host-rendered UI are not physical-device acceptance.
Completed local results:

- 820 Flutter regression checks passed across large screens, player, home,
  settings, library, core settings, Android indexing and smoke coverage.
- After the final TV-only settings alignment and accessible-description polish,
  26 focused TV library/player/settings checks passed, including large text.
- Four native TvStorageFiles JVM checks passed with no failures or errors.
- Targeted production analysis and git diff whitespace checks passed.
- Signed release APK compiled successfully. Signature verification and 16 KiB
  ZIP alignment checks passed; JNI libraries contain only armeabi-v7a.

Preview 6 is `1.35.1-tv-preview.6`, Android version code `3075`, signed with
certificate SHA-256
`8e7ae56aa5b6b4aab8206ce27fb7c0d27e5e5b098653b892d8d2ff395c3451dd`.
The APK SHA-256 is
`32141d12285c9a9e3cb097af2e3a586936ee6f2bf76c7bf51639253be799dc2b`.
It is retained outside the repository as
`kivo-android-tv-preview6-armeabi-v7a.apk` with metadata and actual widget
captures. It has not been installed on the TV. No CI was triggered for this
private preview.

## Physical evidence and remaining acceptance

The physical TV is Android 13, a 1920 by 1080 display at 240 dpi, with a 32-bit
ARM ABI. Earlier signed previews were installed as in-place updates with the
same certificate. No uninstall, application-data clearing or permission bypass
was performed. Custom accent and existing data were preserved.

Preview 5 (1.35.1-tv-preview.5, code 3074) recovered real removable-folder
contents by requesting Android indexing. Native logs changed from zero indexed
entries to a nonzero result, and the owner confirmed the episodes appeared.
This validates that recovery on the real drive; it does not yet validate the
new root-scanning library presentation on hardware.

A particular H.264/MP3 AVI still reproduces a physical playback failure: the
owner observed frozen video while audio progressed, and then both stopped
after a seek. Runtime media metrics identify the Amlogic AVC hardware decoder
for the 720 by 404 stream. A separate short native software-decoding probe with
the shipped libmpv progressed at approximately real time with null outputs.
That probe does not validate audible output or the Flutter surface. An actual
Kivo hardware/software comparison and the freeze/seek recovery remain pending.

The high-resolution playback/seek report concerns the phone. There is no
original failing 4K sample on the connected drive, so no 4K performance fix or
benchmark is claimed. The shared engine, active codec, preview extraction,
render surface and precise-seek recovery need measurement on the original
phone/sample before changing decoder policy.

After capturing the current TV failure, control was returned to the owner at
their request. Further TV input and installation wait for renewed availability.
The unified-library/focus preview is a separate artifact from installed preview
5. It must be physically checked for source discovery, D-pad traversal,
submenus, queue editing, fullscreen output, drive removal and reinsertion.

No public version bump, release tag or public release is part of this preview.
