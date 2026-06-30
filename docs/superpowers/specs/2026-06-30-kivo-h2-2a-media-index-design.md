# Kivo — Hito 2, sub-proyecto 2a: Índice de medios (Diseño)

**Fecha:** 2026-06-30
**Estado:** Diseño aprobado
**Hito:** 2 (biblioteca) — sub-proyecto **2a** (la base). 2b (UI) y 2c (búsqueda/sort/filtros) vienen después, cada uno con su ciclo.

## Visión

Cimiento de la biblioteca: descubrir los videos del dispositivo vía **MediaStore**, exponerlos como un índice con metadatos + agrupación por carpeta + derivación de cola, detrás de una interfaz de plataforma, con flujo de permiso. Incluye un **slice funcional** (lista básica que abre el reproductor con la cola real de su carpeta) que de paso **arregla la cola de un elemento del Hito 1** y desbloquea la futura tira de miniaturas.

## Decisiones (aprobadas)

- **Descubrimiento:** canal propio a **MediaStore** (no `photo_manager`, no escaneo crudo). Coherente con la arquitectura (`DeviceControls`/`FrameExtractor`), APK chico, control total.
- **Permiso:** paquete `permission_handler` (maneja la matriz `READ_MEDIA_VIDEO` Android 13+ / `READ_EXTERNAL_STORAGE` anteriores / acceso parcial Android 14).

## Permiso

`permission_handler` solicita el permiso de video. `mediaPermissionProvider` (AsyncNotifier → enum `granted` | `denied` | `limited`/parcial). La `OpenScreen` muestra un estado "dar acceso a tus videos" con botón cuando falta; al conceder, dispara el escaneo. (En Android 13+ el permiso es `Permission.videos`; en ≤12, `Permission.storage`.)

## Frontera de plataforma — `MediaIndexer`

`lib/platform/interfaces/media_indexer.dart`:
```dart
class VideoItem {
  final String id;        // MediaStore _ID
  final String uri;       // content://… (reproducible por media_kit)
  final String name;      // display name con extensión (clave de resume)
  final String folder;    // BUCKET_DISPLAY_NAME
  final int durationMs;
  final int sizeBytes;
  final int dateAddedMs;
  const VideoItem({required this.id, required this.uri, required this.name,
      required this.folder, required this.durationMs, required this.sizeBytes,
      required this.dateAddedMs});
}

abstract class MediaIndexer {
  /// Todos los videos del dispositivo (MediaStore.Video), sin orden garantizado.
  Future<List<VideoItem>> scan();
}
```

`lib/platform/android/android_media_indexer.dart` — `MethodChannel('kivo/media')`, método `scan` → lista de mapas; el lado Kotlin consulta `MediaStore.Video.Media.EXTERNAL_CONTENT_URI` (columnas `_ID`, `DISPLAY_NAME`, `BUCKET_DISPLAY_NAME`, `DURATION`, `SIZE`, `DATE_ADDED`), construye el `content://` por id, y devuelve la lista. Consulta en un executor de fondo; `result.success` vía `runOnUiThread`. (Las **miniaturas** se añadirán a esta interfaz en 2b — `Future<Uint8List?> thumbnail(String id)` vía `loadThumbnail` — fuera de 2a.)

Provider: `mediaIndexerProvider` (override en `main()` con `AndroidMediaIndexer`).

## Estado / providers

- `mediaIndexProvider` (AsyncNotifier → `List<VideoItem>`): al construir, verifica permiso; si concedido, `scan()`. Expone `refresh()` para re-escanear.
- Helpers puros (`lib/player/library/library_query.dart`, testeables):
  - `Map<String, List<VideoItem>> groupByFolder(List<VideoItem>)` — agrupa por `folder`, videos ordenados con `naturalCompare` por `name`.
  - `List<VideoItem> folderQueueFor(List<VideoItem> all, VideoItem current)` — los videos de la misma carpeta, orden natural; base de la cola.

## Apertura + cola (rewire del Hito 1)

`VideoSession` (en `video_source.dart`) se generaliza para soportar `content://` y la clave de resume estable:
```dart
class VideoSession {
  final String playbackPath; // file path o content:// uri (lo que abre media_kit)
  final String displayName;  // nombre del archivo (fuente de la clave de resume)
  final List<String> queue;  // playbackPaths de la carpeta, orden natural
  final int index;
  String get resumeKey => displayName; // estable (antes: basenameOf(path))
}
```
- **Desde la biblioteca** (slice 2a): tocar un `VideoItem` → `VideoSession(playbackPath: item.uri, displayName: item.name, queue: [uris de la carpeta], index: pos)`.
- **Desde el file picker** (se mantiene): `playbackPath = path`, `displayName = basenameOf(path)`, `queue = [path]` (un elemento; el picker no da carpeta).
- `player_screen` abre `session.playbackPath` y usa `session.resumeKey` (sin cambios de lógica; solo la fuente de la clave pasa de `basenameOf(path)` a `displayName`). Esto **arregla** la cola por carpeta (antes era de 1 por la copia del file picker) cuando se abre desde la biblioteca.

## Slice funcional (OpenScreen temporal)

La `OpenScreen` pasa a: si falta permiso → estado "dar acceso"; si concedido → **lista básica** de todos los videos (nombre + duración formateada), tap → abre el reproductor con su cola de carpeta. "Abrir archivo" (file picker) queda como acción secundaria (`AppBar` o botón). **No** es la UI final (2b trae carpetas, "continuar viendo", miniaturas, estilo).

## Testing

- **Unitario (puro):** `groupByFolder` (agrupa correcto, orden natural), `folderQueueFor` (misma carpeta, orden, índice del actual), `VideoSession.resumeKey` (= displayName).
- **Provider/widget:** `mediaIndexProvider` con un `FakeMediaIndexer` (lista determinista) → estados loading/data; la lista de OpenScreen renderiza los nombres; permiso denegado → estado de acceso.
- **Device:** el query MediaStore real (Kotlin), el permiso runtime, y abrir un `content://` con media_kit + resume por nombre.

## Estructura de archivos

```
lib/platform/interfaces/media_indexer.dart        (VideoItem + MediaIndexer)
lib/platform/android/android_media_indexer.dart    (impl MediaStore)
lib/platform/media_indexer_provider.dart           (provider, override en main)
lib/player/library/media_index.dart                (mediaIndexProvider AsyncNotifier)
lib/player/library/media_permission.dart           (mediaPermissionProvider)
lib/player/library/library_query.dart              (groupByFolder, folderQueueFor — puros)
android/.../MainActivity.kt                          (canal kivo/media)
```
Modificados: `lib/player/open/video_source.dart` (VideoSession generalizado), `lib/ui/player/player_screen.dart` (playbackPath/resumeKey), `lib/ui/home/open_screen.dart` (permiso + lista), `lib/main.dart` (override + permission_handler), `pubspec.yaml` (`permission_handler`), `AndroidManifest.xml` (ya tiene READ_MEDIA_VIDEO; verificar READ_EXTERNAL_STORAGE maxSdk para ≤12).

## Fuera de 2a

Vista de carpetas/lista bonita, "continuar viendo", miniaturas, búsqueda, sort, filtros (2b/2c). Persistencia del índice en Hive (MediaStore ya es un índice rápido del sistema; se consulta on-demand; si el escaneo resulta lento en device, se evalúa caché en 2b).
