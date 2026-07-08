# Kivo — Bug 3: panel de subtítulos desfasado + default "forzado"

**Fecha:** 2026-07-07
**Estado:** Aprobado para plan
**Alcance:** Dos fallos de subtítulos incrustados: (a) el panel de pistas arranca vacío y solo aparece la lista al togggle-ar el switch (artefacto de timing de suscripción); (b) el auto-default elige la pista "forzada" (que no muestra nada) en vez de una pista completa. Debugging sistemático — causas raíz confirmadas en Fase 1.

---

## Causas raíz (confirmadas 2026-07-07)

**(a) Lista vacía hasta togglear.** `track_picker.dart` crea `StreamBuilder`s **frescos** en cada apertura del panel, suscritos a `engine.subtitleTracksStream`/`currentSubtitleTrackStream`, que son `StreamController.broadcast()` de media_kit **sin replay del último valor**. La emisión de `track-list` ya ocurrió durante `engine.open`/`applyDefaultTracks` (consumida por los `.first`), así que un panel abierto después arranca con `snapshot.data == null` → lista vacía, hasta que una nueva emisión (que dispara el toggle vía `setSubtitleTrack`) llega al `StreamBuilder` ya montado. No hay `if(subsOn)` que oculte la lista. (El icono del top-bar acierta porque `currentSubtitleTrackProvider` es un `StreamProvider` de larga vida que sí retiene el último valor.)

**(b) Default "forzado".** `selectSubtitleTrack` ([track_selection.dart:6-22]), sin `preferredLanguage`, cae en "primera pista con `isDefault==true`". `MediaTrack.isDefault` sale solo del flag `default` de mpv; media_kit **no lee el flag `forced`** (no hay `isForced` en `MediaTrack`). Una pista forzada muxeada con `default=1` gana y no muestra nada.

## 1. Fix (a): el picker nunca arranca vacío (snapshot como initialData)

**Engine — getters de snapshot actual.** `PlaybackEngine` (interfaz) + `MediaKitEngine` + `FakePlaybackEngine`:
```dart
List<MediaTrack> get currentSubtitleTracks; // _player.state.tracks.subtitle mapeado/filtrado como el stream
List<MediaTrack> get currentAudioTracks;    // idem audio
MediaTrack? get currentSubtitleTrack;       // _player.state.track.subtitle mapeado (null si no/auto)
MediaTrack? get currentAudioTrack;          // idem audio
```
`MediaKitEngine` los implementa reutilizando `_subtitleToMedia`/`_audioToMedia` y el filtrado de pseudo-pistas (`no`/`auto`) idéntico a los streams. `_player.state.tracks`/`_player.state.track` ya están poblados una vez cargado el medio.

**`track_picker.dart`.** Los `StreamBuilder<List<MediaTrack>>` (lista) y `StreamBuilder<MediaTrack?>` (actual) reciben `initialData:` = el snapshot del engine:
- lista: `initialData: widget.isSubtitles ? engine.currentSubtitleTracks : engine.currentAudioTracks`
- actual: `initialData: widget.isSubtitles ? engine.currentSubtitleTrack : engine.currentAudioTrack`

Así el panel muestra la lista y el resaltado correctos desde el primer frame, sin depender de una emisión futura del broadcast. (El stream sigue conectado para actualizaciones en vivo.)

## 2. Fix (b): despriorizar pistas forzadas en el default

**`track_selection.dart`.** Nuevo helper puro + reescritura de la selección:
```dart
/// Heurística: media_kit no expone el flag `forced` de mpv, así que una pista
/// se trata como forzada si su título o idioma lo indica.
bool looksForced(MediaTrack t) {
  final s = '${t.title ?? ''} ${t.language ?? ''}'.toLowerCase();
  return s.contains('forced') || s.contains('forzad');
}

MediaTrack? selectSubtitleTrack({
  required List<MediaTrack> tracks,
  required bool enabledByDefault,
  String? preferredLanguage,
}) {
  if (!enabledByDefault) return null;
  if (tracks.isEmpty) return null;
  if (preferredLanguage != null) {
    final byLang = tracks.where((t) => t.language == preferredLanguage).toList();
    if (byLang.isNotEmpty) return _preferNonForced(byLang);
  }
  return _preferNonForced(tracks);
}

/// Prefiere pistas NO forzadas; dentro de ellas, una marcada default; si todas
/// son forzadas, cae a la lista completa (mejor algo que nada).
MediaTrack _preferNonForced(List<MediaTrack> tracks) {
  final nonForced = tracks.where((t) => !looksForced(t)).toList();
  final pool = nonForced.isNotEmpty ? nonForced : tracks;
  for (final t in pool) {
    if (t.isDefault) return t;
  }
  return pool.first;
}
```
Comportamiento: subs siguen ON por defecto (`subtitlesEnabledByDefault=true`), pero se elige una pista **completa** (spa/eng) en vez de la forzada. Si el usuario fijó `preferredSubtitleLanguage`, se honra (prefiriendo la no-forzada dentro de ese idioma). El `_turnOn` del switch ([track_picker.dart:283-292]) reusa `selectSubtitleTrack`, así que también se beneficia. La selección de audio no cambia (forced es concepto de subtítulos).

## Unidades y límites

1. **`playback_engine.dart` + `media_kit_engine.dart` + `FakePlaybackEngine`** — 4 getters de snapshot.
2. **`track_selection.dart`** — `looksForced` + `selectSubtitleTrack`/`_preferNonForced` (puro).
3. **`track_picker.dart`** — `initialData` en los dos `StreamBuilder`.

## Testing

- **Unit (`track_selection.dart`):**
  - `looksForced`: título "Forzado"/"forced"/idioma "forced" → true; "spa"/"English" → false.
  - `selectSubtitleTrack`: con [forzado(default), spa, eng] y `enabledByDefault=true`, sin preferido → devuelve spa (primera no-forzada), NO forzado. Con preferido 'eng' → eng. Con `enabledByDefault=false` → null. Con solo forzadas → cae a la primera. Lista vacía → null.
- **Widget/engine:** `FakePlaybackEngine.currentSubtitleTracks` devuelve lo configurado; (si práctico) un test del picker que verifica que la lista aparece con `initialData` aunque el stream no haya emitido. Si montar el picker es costoso, cubrir los getters del fake + verificación en dispositivo.
- **Checklist en dispositivo (release, Pixel 6):**
  - Abrir un video con subs incrustados (forzado/spa/eng): el panel muestra la lista **de inmediato** (no vacío), sin togglear el switch, y repetible al cerrar/abrir.
  - Por defecto se muestra una pista **completa** (spa o eng) y **se ven los subtítulos** (no la forzada muda). El icono del top-bar coincide con la pista real.
  - Elegir manualmente forzado/spa/eng sigue funcionando; togglear el switch off/on respeta la selección.
  - Un video sin subs: panel vacío correcto, icono inactivo (sin regresión).

## Restricciones globales

- No tocar media_kit (no expone `forced`; por eso la heurística).
- Un solo acento; sin colores nuevos.
- Patrón de interfaz de engine (getters en `PlaybackEngine` + impl Android + fake).
- No `flutter run`; build release + `adb install` al Pixel 6 al cerrar.
- Suite completa verde.
