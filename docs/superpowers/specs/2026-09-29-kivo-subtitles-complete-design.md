# Kivo subtítulos completos (tanda 3) — Design

**Date:** 2026-09-29
**Status:** Approved for implementation. Standing autonomy for every tanda
("decide tú y me cuentas al final. Vale para todas las tandas"). Also carries
a user-requested change to tanda 2: the Modo noche card is disabled (and says
why) on non-Dolby tracks instead of letting it be switched on to do nothing.

## What was measured first (it changes the whole tanda)

Kivo builds `Player()` with media_kit's default `PlayerConfiguration`, whose
`libass` is **false**. media_kit then sets `sub-ass=no`, `sub-visibility=no`
and `secondary-sub-visibility=no` in mpv, and draws subtitles itself with the
`Video` widget's `SubtitleView` — a Flutter `Text` fed by mpv's `sub-text`,
with a **fixed style** (white 32 px on `0xaa000000`). Consequences today:

1. The Estilo tab (size, text colour, background) writes `sub-font-size`,
   `sub-color`, `sub-back-color` to mpv, which draws nothing: **the style has
   never reached the screen.** Only the sheet's own preview showed it.
2. **Bitmap subtitles (PGS from Blu-ray, VobSub from DVD, DVB) are never
   shown**: `sub-text` is empty for them and mpv is not drawing.
3. ASS/SSA lose all styling and positioning (`sub-text` is plain).

Turning on media_kit's `libass` mode is not enough either: on Android libass
has no font provider (no fontconfig in this build, `sub-font-provider=none`),
so it only sees fonts in `sub-fonts-dir` and has no per-glyph fallback — CJK,
Arabic, Hebrew, Thai… would render as boxes for any text without embedded
fonts. Flutter's text stack, by contrast, has the system's full fallback.

## Decision: split who draws

| Current track | Drawn by | Why |
|---|---|---|
| Text (SubRip, WebVTT, mov_text, …) | **Kivo** (Flutter overlay) | full user style + every script |
| ASS/SSA, "Respetar estilo ASS" on (default) | **mpv/libass** | file styling, karaoke, typesetting, embedded fonts |
| ASS/SSA, that switch off | Kivo | user style, plain text |
| Bitmap (PGS, VobSub, DVB, XSUB) | **mpv** | the only way they show at all |
| Secondary subtitle | Kivo, always, at the top | mpv 0.36 strips its styling anyway |

- `sub-visibility` follows that table (yes only while mpv draws);
  `sub-ass=yes`; `sub-ass-override=no` (the file's own style when mpv draws
  ASS — the old `force` would have stomped it); `secondary-sub-visibility`
  stays no.
- libass font: the system's Roboto is copied once into the app's files dir
  (`/system/fonts/Roboto-Regular.ttf`, fallbacks `RobotoStatic-Regular.ttf`,
  `DroidSans.ttf`) and handed over as `sub-fonts-dir` + `sub-font`. If no
  font can be prepared, ASS goes to Kivo's overlay instead (never boxes).
- media_kit's own `SubtitleView` is switched off
  (`SubtitleViewConfiguration(visible: false)`).
- The track's codec comes from mpv `current-tracks/sub/codec`, re-read on
  subtitle track/list events.

## Kivo's overlay

- One widget (`SubtitleText`) renders both the live overlay and the Estilo
  preview, so the preview is truly WYSIWYG.
- Style: size (existing, logical px at a 360 dp short side, scaled to the
  player's short side), text colour, background (existing), **outline**
  width 0–5 + colour, **shadow** on/off, **bold**, **font** (Predeterminada ·
  Serif · Monoespaciada · Condensada — Android's own `sans-serif`, `serif`,
  `monospace`, `sans-serif-condensed`, so every script keeps its fallback),
  **position** (bottom margin, % of height 0–40) and the secondary's top
  margin (0–40).
- Subtitles lift above the bottom controls while those are showing (animated),
  and the secondary drops below the top bar likewise.
- Outside the zoom transform: pinch-zoom enlarges the picture, not the text.
  Also drawn in PiP.
- Defaults: outline 2 black, shadow on, not bold, default font, 6 % / 6 %,
  Respetar estilo ASS on. (The background stays transparent by default — the
  outline is what makes it readable now.)

## Secondary subtitle

In the Pistas tab, a "Segundo subtítulo" section: Desactivado + every
non-bitmap track other than the primary. Choosing one sets `secondary-sid`
and remembers its language as `secondarySubtitleLanguage`; every open picks
the embedded track in that language (not the primary) or writes
`secondary-sid=no` — unconditionally, since it is a global mpv option.

## Settings

`subtitleOutlineWidth 2.0`, `subtitleOutlineColor 0xFF000000`,
`subtitleShadow true`, `subtitleBold false`, `subtitleFontFamily 'default'`,
`subtitleBottomMargin 6.0`, `secondarySubtitleTopMargin 6.0`,
`subtitleRespectAss true`, `secondarySubtitleLanguage null`.

## Architecture

- `lib/player/subtitles/subtitle_render.dart` — pure: codec classes and
  `drawerFor(codec, hasTrack, respectAss, fontsReady)`.
- `lib/player/subtitles/subtitle_render_controller.dart` — app-scoped: font
  setup at start, re-derives the drawer on track events and on the setting,
  writes `sub-visibility` only on change, publishes `subtitleDrawerProvider`.
- Engine: `subtitleTextStream`, `currentSubtitleCodec()`,
  `setSubtitleRendering(mpvDraws)`, `configureSubtitleFonts(dir, family)`,
  `setSecondarySubtitleTrack(id?)`; `MediaTrack.codec`. `setSubtitleStyle`
  goes away (it styled nothing).
- Kotlin: `kivo/subtitles` gains `systemFont` → `{dir, family}`.

## Testing

Pure drawer table; controller (writes on change only, fonts-missing fallback,
setting change); overlay widget (style → TextStyle/outline/shadow/position,
hidden when mpv draws, secondary at top, lifts with controls); settings
round-trips; secondary pick + per-open reset regression; Estilo tab controls.

## Branch review (applied)

- `secondary-sub-text` goes unavailable (not empty) when the secondary is
  switched off and media_kit keeps the last cue: the overlay draws the
  secondary only while `secondarySubtitleTrackId` is set, read per text event.
  Turning subtitles off also clears the secondary.
- mpv refuses a track held by the other slot (`sid`/`secondary-sid`, both
  global): each open writes `secondary-sid=no` before picking the primary;
  picking the secondary's track as primary frees it first; the engine reads
  `secondary-sid` back instead of trusting its own write; candidates exclude
  the primary by mpv's number (`current-tracks/sub/id`), not only by the uri
  media_kit reports for an external primary.
- The lift above the controls follows what is actually drawn (not locked, no
  sync panel, not PiP); bar heights are reported from layout itself.
- `dvb_teletext` counts as a picture subtitle.
- Accepted: switching the primary blanks the current secondary cue until its
  next one (media_kit resets both lines on a track change).
