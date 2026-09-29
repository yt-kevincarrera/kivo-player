# Kivo reproducción robusta (tanda 1) — Design

**Date:** 2026-09-29
**Status:** Approved for implementation. The user chose: decoder control =
global setting + in-player control remembered per video; auto-fallback =
switch silently, toast with "Deshacer", remember; encoding picker = curated
names by language/region + technical name + "Más…"; both halves via approach 1
(runtime `hwdec` switch; native detect+transcode). Then: "no me hagas más
preguntas, haz lo que creas mejor" — every remaining choice below is mine and
is listed in the final report.

## Goal

Que cualquier archivo se vea y que cualquier subtítulo externo se lea bien.

## What was measured before designing

- media_kit_video 2.0.1 on Android sets `hwdec=auto-safe` (→ `mediacodec-copy`
  with `vo=gpu`), `hwdec-codecs=h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1`.
  mpv already falls back to software when the hardware decoder fails to
  *initialise*. What nobody catches: hardware "works" but no frame ever
  arrives (frozen/black picture, audio running), or the picture is garbage
  (green, blocks) — the latter is not detectable at all.
- The bundled `libmpv.so` has **no uchardet** (no charset autodetection) and no
  `iconv_open` symbol. mpv reads non-UTF-8 text subtitles as `UTF-8-BROKEN`
  (invalid bytes as Latin-1). So Spanish Latin-1 `.srt` files already look
  mostly right; what breaks is Windows-1252's own range (“ ” ‘ ’ – — …) and
  every non-Latin encoding (Cyrillic, Greek, Arabic, Hebrew, Turkish, CJK,
  Thai…). Embedded text tracks in MKV are UTF-8 by spec — this only concerns
  external files.
- All external subtitle loads go through `PlaybackEngine.setExternalSubtitle`
  from four call sites: `applyDefaultTracks` (folder match + remembered
  hand-picked file), `ManualSubtitleController.load`, and the picker's
  folder list. media_kit implements it as `sub-add <uri> select`.
- `hwdec` is a global mpv option on the process-lifetime `Player` — like
  `sub-delay`/`af` it survives `loadfile` (see mpv-global-properties), so it
  must be written unconditionally on every open.

## Part 1 — Decoder

### Modes

`DecoderMode { auto, hardware, software }`, stored as `'auto' | 'hw' | 'sw'`.

| Mode | mpv `hwdec` | Kivo watchdog |
|---|---|---|
| auto (default) | `auto-safe` | on (if the setting is on) |
| hardware | `auto-safe` | off — mpv's own init fallback still applies |
| software | `no` | off |

### Resolution

Effective mode for a video = its per-video override, else the global
`KivoSettings.decoderMode`. The per-video override lives in
`VideoTrackPrefs.decoder` (`'hw' | 'sw' | null`), so rename migration, delete
cleanup and backup/restore come for free. The in-player control shows the
*effective* mode; choosing the value equal to the global one clears the
override (nothing stored), any other value stores it. That keeps "remembered
for this video" meaning exactly "differs from your default".

### Watchdog (auto mode, hardware actually active)

Armed per open. A wall-clock timer of `decoderStallSeconds` (default 3,
1–10) runs only while **all** hold: playing, not buffering, video output
enabled (not audio-only/background `vid=no`), no first frame yet. Any
condition breaking cancels the timer; the first frame disarms the watchdog for
the rest of that session. On fire, it re-checks: the file has a real video
track, and `hwdec-current` is a hardware decoder (not `no`/empty). Wall clock,
not media time, because a stalled video decoder can also stall mpv's clock.

### Fallback

- **Stall:** `hwdec=no` live, then seek to the current position to force a
  fresh frame. Per-video override saved as `sw`.
- **Open failure with hardware:** before surfacing KV-501, set `hwdec=no` and
  retry the open once at the same start position. If that works, same outcome
  as a stall. If it fails too, KV-501 as today.
- Both record **KV-504** ("El video no se mostraba con el decodificador por
  hardware") in the error log with the technical reason, and publish a
  fallback event. The player screen (when visible) shows
  *"Cambiado a decodificación por software"* with **Deshacer**.
- **Deshacer** stores the explicit `hw` override (not auto → no loop) and
  applies it live.

### Live switch

`engine.setHwdec(value)` + `engine.seek(position)`. Tracks, delays, EQ and
position are kept (decoder reinit only). Risk: not verified on a device from
this session — mpv-android does exactly this at runtime, which is the basis
for the choice.

### UI

- **More menu → Reproducción:** row "Decodificador" with a segmented pill
  `Auto · HW · SW`; subtitle shows what is really active ("Activo: hardware" /
  "Activo: software", read from `hwdec-current`) plus "· solo este video" when
  an override exists.
- **Ajustes → Reproducción avanzada → Decodificación:** default mode (choice),
  "Cambio automático a software" (switch), "Espera antes de cambiar" (stepper
  1–10 s), "Olvidar decodificadores guardados" (clears every per-video
  override; snackbar with the count).
- Info overlay unchanged (it is a name/time corner label; the active decoder
  lives in the menu row where it can also be changed).

### Settings

`decoderMode: 'auto'`, `decoderAutoFallback: true`, `decoderStallSeconds: 3`.

## Part 2 — Subtitle encoding

### Native `kivo/subtitles` (new `SubtitleCharsets.kt`, not MainActivity)

`prepare {uri, name?, encoding?}` → `{path, encoding, detected}`:
1. Read the bytes (`content://` via ContentResolver, `file://` or plain path
   via File). Cap 20 MB.
2. Binary (NUL byte in the first 4 KB with no UTF-16 BOM — VobSub `.sub`) →
   pass through untouched, `encoding=null`.
3. No manual encoding: UTF-8 BOM or strictly valid UTF-8 → pass through,
   `UTF-8`. UTF-16 BOM → convert. Otherwise detect with
   `android.icu.text.CharsetDetector` (API 24+), taking the first match Java
   can decode; `ISO-8859-1` is promoted to `windows-1252` (superset, what
   browsers do). Below API 24 or no match → `windows-1252`. `detected=true`.
4. Manual encoding: decode with it (errors replaced), `detected=false`.
5. Write UTF-8 (no BOM) to `cacheDir/subtitles-utf8/<sha1(uri|enc)>.<ext>`
   (ext from `name`, else the uri, else `srt`); keep the newest 40 files.

`encodings` → `Charset.availableCharsets().keys`.

### Dart

- `SubtitleTranscoder` interface + `AndroidSubtitleTranscoder`; provider throws
  when not overridden.
- `SubtitleLoader` (one place for all four call sites): reads the per-video
  `VideoTrackPrefs.subtitleEncoding`, prepares, hands mpv the result. A
  transcoder failure logs KV-502 and falls back to the raw uri (today's
  behaviour) — never blocks a subtitle. Publishes `activeExternalSubtitle`
  (source uri, title, encoding, detected) for the picker; cleared on every
  open, on picking an embedded track and on turning subtitles off.
- `reloadWithEncoding(String? enc)`: saves (null = automatic), then removes the
  current external track (`sub-remove`) and adds the re-prepared one, so the
  track list does not grow a duplicate per attempt.

### UI

In the Pistas tab, when an external subtitle is showing: a card
"Codificación · Automático (detectado: Cirílico)" / "Codificación · Cirílico".
Tap → sheet: Automático, then the curated list (label + technical name),
then "Más…" expanding every other charset the system has.

Curated list: Unicode (UTF-8) · Europa occidental (windows-1252) · Europa
central (windows-1250) · Cirílico (windows-1251) · Griego (windows-1253) ·
Turco (windows-1254) · Hebreo (windows-1255) · Árabe (windows-1256) · Báltico
(windows-1257) · Vietnamita (windows-1258) · Tailandés (TIS-620) · Chino
simplificado (GBK) · Chino tradicional (Big5) · Japonés (Shift_JIS) · Coreano
(EUC-KR). Detected names map onto these labels by alias (ISO-8859-5/KOI8-R →
Cirílico, GB18030/GB2312 → Chino simplificado, EUC-JP → Japonés, ISO-8859-2 →
Europa central, …); unknown names show raw.

Small fix riding along: the picker's folder-subtitle card never showed as
active (it compared mpv's numeric track id with a content uri); it now reads
`activeExternalSubtitle`.

## Error codes

Append `KivoOp.decoderFallback` → `KV-504`. KV-502 reused for a failed
transcode.

## Testing

Pure/unit: mode resolution + mpv mapping; watchdog under fake_async (fires,
cancels on pause/buffering/vid=no, disarms on frame, never for software or
no-video); controller: open-failure retry, stall fallback, undo, pill
clearing, **unconditional `hwdec` write per open** (open A with `sw`, open B
without → B gets `auto-safe`); `VideoTrackPrefs`/`KivoSettings` round-trips
incl. legacy maps; encoding label mapping; loader (override passed, fallback
on failure, replace on reload). Widget: menu row, settings group, encoding
card + sheet. Native code is not unit-tested (no JVM test setup in the repo);
it is kept small and pure-ish.

## Out of scope

Detecting garbled-but-present frames (impossible); a custom libmpv build;
encoding for embedded tracks (already UTF-8).
