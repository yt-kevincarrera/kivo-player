# Kivo audio de cine (tanda 2) — Design

**Date:** 2026-09-29
**Status:** Approved for implementation. The user chose approach A (use what
the bundled libmpv has; no custom libmpv build) and "decide tú y me cuentas al
final" — every choice below is mine and goes in the final report.

## Goal

Diálogos que se entienden y explosiones que no despiertan a nadie, sin
recompilar libmpv.

## What was measured (the hard limit)

- The bundled FFmpeg is built with `--disable-filters` + only
  `--enable-filter=overlay,equalizer` (media-kit/libmpv-android-video-build
  `flavors/default.sh`; confirmed by the binary's symbols: `ff_af_equalizer`,
  `ff_asrc_abuffer`, `ff_asink_abuffer` and nothing else audio). No
  `acompressor`, `dynaudnorm`, `loudnorm`, `pan`, **`volume`**.
- **Existing bug:** `mpvAudioFilter` appends `volume=<preamp>dB` to the lavfi
  graph when the EQ preamp is non-zero. That filter does not exist here, so
  with any preamp the whole `af` is rejected and the equalizer is silently off.
- mpv is 0.36-dev. What it offers without FFmpeg filters (read in the v0.36.0
  source):
  - `replaygain-fallback=<dB>` — applied whenever ReplayGain mode is `no`
    (our default), `UPDATE_VOL` (live). A pure software gain.
  - `ad-lavc-ac3drc=<0..6>` — FFmpeg's `drc_scale` for AC-3/E-AC-3: the
    Dolby dynamic range compression carried in the stream. No update flag:
    read at decoder init only.
  - `audio-channels`, `audio-swresample-o` (swresample `center_mix_level`,
    `surround_mix_level`, `lfe_mix_level`), `audio-normalize-downmix` —
    `UPDATE_AUDIO` (live, reloads the audio chain).

## Features

### Modo noche
Dolby DRC on AC-3/E-AC-3 tracks: `ad-lavc-ac3drc` = Suave 1.0 (as authored),
Media 2.0, Fuerte 4.0. Other codecs: no effect — and the UI says so, per track.
Toggling while an AC-3/E-AC-3 track plays reinitialises its decoder
(`aid=no` → `aid=<id>`), a sub-second audio gap.

### Realzar voces
- Multichannel source (> 2 ch): downmix to stereo with the centre (dialogue)
  raised and the surrounds lowered: `audio-channels=stereo` +
  `audio-swresample-o=center_mix_level=C,surround_mix_level=0.5`, C = Suave
  1.0, Media 1.41, Fuerte 2.0 (swresample's default is 0.707). LFE stays at
  swresample's default (dropped), which also tames explosions.
- Stereo/mono source: a voice-clarity curve added to the equalizer bands
  (bass/rumble down, 1–4 kHz up), scaled by the level, with a small negative
  gain to keep the boost from clipping. Summed onto the user's own EQ, clamped
  to ±12 dB per band.
- `audio-channels=stereo` + the mix levels are written whenever the feature is
  on, whatever the source, so switching tracks never reloads the audio chain
  just for that.

### Preamp fix
The EQ preamp moves out of the lavfi graph into `replaygain-fallback`.
`mpvAudioFilter` never emits `volume=` again.

## Architecture

- `lib/player/audio/audio_pipeline.dart` — pure: `AudioSource{codec,
  channels}`, `EnhancementLevel{soft,medium,strong}`, `AudioPipeline{af,
  gainDb, forceStereo, swresample, drc}` and `buildAudioPipeline(eq, night,
  nightLevel, voice, voiceLevel, source)`. All mapping tables live here.
- `lib/player/audio/audio_pipeline_controller.dart` — app-scoped: the ONLY
  writer of `af`, `replaygain-fallback`, `audio-channels`,
  `audio-swresample-o`, `ad-lavc-ac3drc`. Keeps a cache of what it last wrote
  and writes only differences (these are global mpv options that survive
  loadfile, and nothing else writes them, so the cache mirrors mpv; the
  `UPDATE_AUDIO` ones would otherwise reload the audio chain on every open).
  Recomputes on: an open (`applyDefaultTracks`), the audio track or track list
  changing (source codec/channels), the enhancement settings changing, and the
  equalizer's debounced apply. Reloads the audio decoder when the DRC value
  changes under a Dolby track.
- Engine: `setAudioGain(db)`, `setAudioDownmix({forceStereo, swresample})`,
  `setDolbyDrc(scale)`, `reloadAudioDecoder()`, `currentAudioSource`.
- `EqualizerNotifier._apply` hands its settings to the pipeline controller
  instead of writing `af` itself.

## UI

- Player ⋮ → Audio group, under Ecualizador: **Modo noche** and **Realzar
  voces**, each an Off/On pill with a per-track status line ("Comprimiendo la
  pista Dolby" / "Sin efecto: esta pista no es Dolby"; "Mezcla 5.1 con el
  centro realzado" / "Ecualización de voz").
- Ajustes → Reproducción avanzada → **Audio**: both switches plus an
  Intensidad choice (Suave · Media · Fuerte) for each.
- Global settings (not per video): night is a time of day, not a file.
  Defaults: both off, level Media.

## Settings

`nightMode: false`, `nightModeLevel: 'medium'`, `voiceBoost: false`,
`voiceBoostLevel: 'medium'`.

## Testing

Pure pipeline table tests (every combination that matters, preamp never in
`af`, clamping, stereo vs multichannel, unknown source); controller: diff-only
writes, decoder reload only for Dolby + DRC change, EQ path, per-open apply;
widget: menu rows + status lines, settings group. Existing equalizer tests
updated for the preamp move.

## Out of scope

Real dynamic compression / loudness normalisation for non-Dolby tracks — needs
FFmpeg filters, i.e. our own libmpv build (option B, deferred).
