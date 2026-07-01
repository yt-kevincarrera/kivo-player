# Kivo Hito 3 / 3a — Subtítulos y pistas de audio (Diseño)

**Fecha:** 2026-07-01
**Estado:** Diseño aprobado.
**Contexto:** Primer sub-proyecto de Hito 3 (funcionalidad avanzada del reproductor). Hitos 1 y 2 están completos. El reproductor ya tiene botones deshabilitados en la barra superior reservados para esto ("Subtítulos", "Audio"). 3b (sleep timer), 3c (bucle A-B), 3d (Picture-in-Picture) y 3e (segundo plano/audio-only) siguen después, en ese orden.

## 1. Alcance

- **Pistas de audio y subtítulos incrustadas en el video:** media_kit/libmpv ya las expone (`Player.state.tracks`/`stream.tracks`) — es sobre todo UI de selección.
- **Subtítulos externos (archivo aparte en la misma carpeta):** descubrimiento automático, **solo para videos abiertos desde la biblioteca** (los videos indexados vía MediaStore usan URIs `content://`; no hay una forma confiable de listar arbitrariamente el contenido de una carpeta a partir de eso con `dart:io`, a diferencia de una ruta de archivo real). Requiere una consulta nativa nueva a `MediaStore.Files` filtrada por la carpeta del video y extensiones de subtítulo. Videos abiertos por selector de archivos/compartir solo ofrecen pistas incrustadas.
- **Personalización visual de subtítulos:** tamaño de fuente, color de texto, color de fondo — vía las propiedades nativas de libmpv (`sub-font-size`, `sub-color`, `sub-back-color`), que media_kit expone a través de `Player.setProperty(String, String)` (confirmado en el código fuente del paquete). Se fija `sub-ass-override=force` para que el estilo elegido se aplique de forma consistente incluso sobre pistas con estilo ASS/SSA propio incrustado.
- **Libass sigue renderizando los subtítulos de forma nativa** sobre el video (quemados en el frame) — no hay overlay de Flutter para el texto en sí.

## 2. Comportamiento por defecto

Dos campos en `KivoSettings`:
- `subtitlesEnabledByDefault` (`bool`, default `true`).
- `preferredSubtitleLanguage` (`String?`, default `null`).

Al abrir cualquier video:
- Si `subtitlesEnabledByDefault == false` (el usuario los apagó explícitamente la última vez): subtítulos apagados, sin importar qué pistas tenga el video. Se mantiene así hasta que el usuario los reactive manualmente.
- Si `subtitlesEnabledByDefault == true` (el caso normal, y el default de una instalación nueva): si el video tiene pistas y `preferredSubtitleLanguage` coincide con alguna, se aplica esa; si no hay coincidencia (o nunca se eligió un idioma), se usa la pista marcada como predeterminada por el contenedor (`isDefault`), o si ninguna lo está, la primera disponible. Resultado: **si el video trae subtítulos, se muestran solos**, salvo que el usuario los haya apagado antes.

Cada vez que el usuario **elige manualmente** una pista con idioma conocido, se actualiza `preferredSubtitleLanguage`. Cada vez que elige "Desactivado" explícitamente, `subtitlesEnabledByDefault` pasa a `false`; al elegir cualquier pista (incluidos archivos externos sin idioma detectado), vuelve a `true`.

Los archivos externos descubiertos por carpeta **no participan en el auto-match** salvo que su nombre siga un patrón común de idioma (p. ej. `Pelicula.es.srt`) — en ese caso si coincide con `preferredSubtitleLanguage` también se auto-aplican.

**Audio:** análogo pero más simple — `preferredAudioLanguage` (`String?`). Al abrir un video, si hay una pista de audio con ese idioma, se selecciona; si no, se deja la que el contenedor marque como predeterminada (comportamiento normal de reproducción, sin cambios visibles la mayoría de las veces). No existe un estado "apagado" para audio.

## 3. Personalización de subtítulos

Tres campos nuevos en `KivoSettings` (globales, mismo patrón que `accentColor`):
- `subtitleFontSize` (`double`, default `26.0`).
- `subtitleTextColor` (`int` ARGB, default blanco `0xFFFFFFFF`).
- `subtitleBackgroundColor` (`int` ARGB, default negro semi-opaco `0xB3000000` — ~70% opacidad, mejor legibilidad que transparente).

Se aplican al abrir cada video (y al cambiarlos desde ajustes, en caliente) vía `PlaybackEngine.setSubtitleStyle(fontSize, textColorArgb, backgroundColorArgb)`, que en `MediaKitEngine` se traduce a `player.setProperty('sub-font-size', fontSize.toString())` y `player.setProperty('sub-color', '#AARRGGBB')`/`player.setProperty('sub-back-color', '#AARRGGBB')` (mpv acepta color en formato hex `#AARRGGBB` de 8 dígitos para estas propiedades — el ARGB de Flutter se reformatea a esa cadena), y fija `sub-ass-override=force` una vez al abrir el motor.

## 4. Interfaz de `PlaybackEngine`

Nuevo modelo propio (no se filtran tipos de media_kit por el borde de la plataforma):

```dart
class MediaTrack {
  final String id;
  final String? title;
  final String? language;
  final bool isDefault;
  const MediaTrack({required this.id, this.title, this.language, this.isDefault = false});
}
```

Añadidos a `PlaybackEngine`:
```dart
Stream<List<MediaTrack>> get audioTracksStream;
Stream<List<MediaTrack>> get subtitleTracksStream;
Stream<MediaTrack?> get currentAudioTrackStream;
Stream<MediaTrack?> get currentSubtitleTrackStream; // null = apagado
Future<void> setAudioTrack(String id);
Future<void> setSubtitleTrack(String? id); // null = apagar
Future<void> setSubtitleStyle({required double fontSize, required int textColorArgb, required int backgroundColorArgb});
```

## 5. Descubrimiento de subtítulos externos (nativo)

Nuevo método en el canal `kivo/media` (`MainActivity.kt`): dado el `id` de MediaStore del video (o su carpeta), consulta `MediaStore.Files.getContentUri("external")` filtrando por la misma carpeta (`BUCKET_DISPLAY_NAME`/ruta relativa) y extensión en `{srt, vtt, ass, ssa, sub}`, devolviendo lista de `{uri, displayName}`. Se usa `SubtitleTrack.uri(...)` de media_kit para aplicar el archivo elegido.

## 6. UI

Bottom sheet (mismo lenguaje visual que `SpeedPanel`: fondo `KivoColors.panel`, esquinas redondeadas arriba, manija de arrastre, dorado para la opción activa), abierto desde los botones ya existentes "Subtítulos"/"Audio" en `top_bar.dart` (hoy deshabilitados):

- **Subtítulos:** "Desactivado" primero, luego pistas incrustadas (título/idioma), luego archivos externos encontrados en la carpeta (solo si es video de biblioteca) — la opción activa resaltada. Al final del sheet, un pequeño acceso a personalización: slider de tamaño + un selector de color simple para texto y fondo (una fila de swatches predefinidos — blanco/negro/amarillo/etc. — no existe hoy un color picker genérico en el proyecto, así que este es nuevo y deliberadamente acotado, no un selector RGB completo).
- **Audio:** lista de pistas incrustadas (título/idioma), la activa resaltada. Sin opción de apagar.
- Los íconos de la barra superior se tiñen con el color de acento cuando hay subtítulos activos (mismo patrón que el ícono de info ya existente).

## 7. Archivos (orientativo)

```
lib/player/engine/playback_engine.dart      (+ MediaTrack, streams de tracks, setAudioTrack, setSubtitleTrack, setSubtitleStyle)
lib/player/engine/media_kit_engine.dart     (mapeo Tracks/AudioTrack/SubtitleTrack de media_kit -> MediaTrack; setProperty para estilo)
android/.../MainActivity.kt                  (+ kivo/media: findSubtitlesNear)
lib/platform/interfaces/media_indexer.dart  (o interfaz nueva: SubtitleFinder, para el folder-scan)
lib/core/settings/kivo_settings.dart        (+ subtitlesEnabledByDefault, preferredSubtitleLanguage, preferredAudioLanguage, subtitleFontSize, subtitleTextColor, subtitleBackgroundColor)
lib/ui/player/tracks/track_picker.dart      (nuevo: bottom sheet compartido subtítulos/audio + panel de estilo)
lib/ui/player/controls/top_bar.dart         (activar botones Subtítulos/Audio, tinte cuando hay subtítulos activos)
```

## 8. Testing

- **Puro:** mapeo de tracks de media_kit a `MediaTrack`; lógica de auto-selección por idioma (con/sin coincidencia, con `subtitlesEnabledByDefault` en ambos estados); parseo de patrón de idioma en nombre de archivo externo (`Pelicula.es.srt` → `es`).
- **Widget:** el bottom sheet lista pistas + resalta la activa; elegir una pista la aplica y actualiza la preferencia; elegir "Desactivado" apaga y persiste; el panel de estilo cambia tamaño/colores.
- **Device:** un video con subtítulos incrustados los muestra solo al abrir (comportamiento por defecto); apagarlos se recuerda en el siguiente video; elegir un idioma se recuerda y se auto-aplica cuando existe coincidencia; un archivo .srt suelto en la carpeta de un video de biblioteca aparece en la lista y se puede aplicar; los ajustes de tamaño/color/fondo se ven reflejados en el subtítulo renderizado, incluso sobre una pista ASS con estilo propio.

## Fuera de alcance

- Selector de archivo manual (file-picker) para subtítulos.
- Descubrimiento de subtítulos externos para videos no-biblioteca.
- Selección de pista de video (multi-ángulo) — infrecuente, no se pidió.
- 3b (sleep timer), 3c (bucle A-B), 3d (PiP), 3e (segundo plano/audio-only).
