# Kivo — Menú ⋮ de la biblioteca: operaciones de archivo

**Fecha:** 2026-07-07
**Estado:** Aprobado para plan
**Alcance:** Activar el botón ⋮ (hoy muerto, `onOptions: null`) de cada video en la biblioteca con cuatro operaciones: **Compartir**, **Renombrar**, **Detalles**, **Borrar**. Android-first, sobre MediaStore/scoped storage.

---

## Contexto

Cada tile de la biblioteca tiene un `IconButton` de opciones (⋮) que hoy está cableado a `onOptions: null` en los dos call sites de [video_density_feed.dart](../../../lib/ui/home/widgets/video_density_feed.dart) (líneas ~197 y ~226) — el botón aparece pero no hace nada.

Datos del modelo:
- `VideoItem` ([media_indexer.dart](../../../lib/platform/interfaces/media_indexer.dart)) expone `id`, `uri` (una URI `content://` de MediaStore), `name`, `folder`, `durationMs`, `sizeBytes`, `dateAddedMs`. **No** tiene resolución ni ruta.
- El índice se refresca con `mediaIndexProvider.refresh()` ([media_index.dart](../../../lib/player/library/media_index.dart)).
- El progreso ("continuar viendo") y el estado "reproducido/Nuevo" se llavean por **nombre de archivo** (`VideoSession.resumeKey => displayName`; [continue_watching.dart](../../../lib/player/library/continue_watching.dart) mapea las entradas de resume por `v.name`; `played` guarda por nombre). Por eso **renombrar migra esas llaves** y **borrar las limpia**.
- El patrón de plataforma: interfaz en `lib/platform/interfaces/`, impl Android en `lib/platform/android/` sobre un `MethodChannel`, provider throws-until-overridden, override en `main.dart`.
- `receive_sharing_intent` ya está (compartir **entrante**). Compartir-hacia-afuera se hará con un intent nativo, **sin** dep nueva.

---

## 1. Frontera de plataforma: `MediaFileOps`

Nueva interfaz separada de `MediaIndexer` (interfaz segregada; `MediaIndexer` sigue enfocado en scan/thumbnail).

`lib/platform/interfaces/media_file_ops.dart`:

```dart
/// Resultado de una operación de archivo que puede requerir consentimiento del
/// sistema (el usuario puede cancelar el diálogo del SO).
enum FileOpStatus { ok, cancelled, error }

class RenameOutcome {
  final FileOpStatus status;
  final String? newName; // nombre final (con extensión) si status == ok
  const RenameOutcome(this.status, {this.newName});
}

/// Operaciones sobre un archivo de video del dispositivo (MediaStore en Android).
abstract class MediaFileOps {
  /// Borra el archivo. En Android 11+ el SISTEMA muestra su propio diálogo de
  /// confirmación; devuelve [FileOpStatus.cancelled] si el usuario lo rechaza.
  Future<FileOpStatus> delete(String uri);

  /// Renombra el DISPLAY_NAME conservando la extensión. [newBaseName] es solo
  /// el nombre base (sin extensión). En Android 11+ el SISTEMA pide
  /// consentimiento de escritura.
  Future<RenameOutcome> rename(String uri, String newBaseName);

  /// Comparte el archivo vía ACTION_SEND (fire-and-forget; el chooser del SO
  /// maneja el resto).
  Future<void> share(String uri);
}
```

`lib/platform/media_file_ops_provider.dart`: `mediaFileOpsProvider` (Provider throws-until-overridden), override en `main.dart` con `AndroidMediaFileOps`.

## 2. Impl Android (`AndroidMediaFileOps` + Kotlin)

`lib/platform/android/android_media_file_ops.dart` habla por el canal `kivo/media` (ya existente) con métodos nuevos: `delete`, `rename`, `share`.

Kotlin (en el handler del canal `kivo/media` + `MainActivity`):

- **`share(uri)`**: `Intent(ACTION_SEND)`, `type="video/*"`, `putExtra(EXTRA_STREAM, Uri.parse(uri))`, `addFlags(FLAG_GRANT_READ_URI_PERMISSION)`, `startActivity(Intent.createChooser(...))`. Devuelve inmediatamente.

- **`delete(uri)`** por nivel de API:
  - **API 30+**: `MediaStore.createDeleteRequest(resolver, listOf(uri))` → `startIntentSenderForResult(pendingIntent.intentSender, REQ_DELETE, ...)`. El SO muestra su diálogo. El resultado (`RESULT_OK`/`RESULT_CANCELED`) vuelve por `onActivityResult` → se resuelve el `Result` pendiente con `ok`/`cancelled`.
  - **API 29**: `resolver.delete(uri, null, null)` dentro de try/catch; si `RecoverableSecurityException` → lanzar `e.userAction.actionIntent.intentSender` por `startIntentSenderForResult` (mismo flujo de resultado).
  - **API 21–28**: `resolver.delete(...)` directo (hay `WRITE_EXTERNAL_STORAGE`).
  - Excepciones inesperadas → `error`.

- **`rename(uri, newBaseName)`** por nivel de API:
  - El nombre final = `newBaseName` + extensión original (derivada del `DISPLAY_NAME` actual).
  - **API 30+**: `MediaStore.createWriteRequest(resolver, listOf(uri))` → `startIntentSenderForResult(REQ_RENAME)`. Al `RESULT_OK`, `resolver.update(uri, ContentValues().apply { put(DISPLAY_NAME, finalName) }, null, null)` → resolver con `ok` + `newName=finalName`. `RESULT_CANCELED` → `cancelled`.
  - **API < 30**: `resolver.update(...)` directo; `ok`/`error`.
  - El intent-sender pendiente lleva el `finalName` para aplicarlo tras el consentimiento.

- **Plomería de `onActivityResult`** en `MainActivity`: request codes `REQ_DELETE`/`REQ_RENAME`, un `MethodChannel.Result` pendiente por operación (una a la vez), resuelto en `onActivityResult`. Si la activity muere en el proceso, el `Result` se abandona (no crash).

**Concurrencia:** una operación con-consentimiento a la vez (guardar el `Result` pendiente; si llega otra mientras hay una en curso, responder `error`). Es una UI de menú contextual — no hay caso real de dos simultáneas.

## 3. Enriquecer el scan para Detalles

`VideoItem` gana tres campos **opcionales con default** (para no romper ninguna construcción/tests existentes):

```dart
final int width;   // px, 0 si desconocido
final int height;  // px, 0 si desconocido
final String path; // RELATIVE_PATH de MediaStore, '' si desconocido
```

`AndroidMediaIndexer.scan` y el lado Kotlin agregan las columnas `WIDTH`, `HEIGHT`, `RELATIVE_PATH` de `MediaStore.Video.Media`.

## 4. Orquestación (Dart): `VideoActionsController`

`lib/player/library/video_actions.dart` — un controlador (provider) que envuelve `MediaFileOps` + los stores + el refresh del índice. Métodos:

```dart
Future<FileOpStatus> delete(VideoItem v);
Future<RenameOutcome> rename(VideoItem v, String newBaseName);
Future<void> share(VideoItem v);
```

- **delete**: llama `ops.delete(v.uri)`; si `ok` → `resumeStore.remove(v.name)` + `playedStore.remove(v.name)` + `mediaIndexProvider.refresh()` + invalidar `continueWatchingProvider`/`playedKeysProvider`. `cancelled`/`error` → no toca stores.
- **rename**: llama `ops.rename(v.uri, base)`; si `ok` con `newName` → **migrar llaves por nombre**:
  - resume: buscar la entrada de `v.name` en `resume.entries()`; si existe, `resume.put(newName, e.seconds, e.updatedAtMs)` (preserva la marca de tiempo original, para que el video renombrado **no** salte al tope de "continuar viendo") y luego `resume.remove(v.name)`.
  - played: `if (played.isPlayed(v.name)) { played.markPlayed(newName); played.remove(v.name); }`.
  - luego `refresh()` + invalidaciones.
- **share**: `ops.share(v.uri)` directo.

`PlayedStore` gana `Future<void> remove(String key)` (Hive: `box.delete(key)`; InMemory: `_s.remove(key)`) — hoy no existe y hace falta para migrar/limpiar.

Helper puro `sanitizeRenameTarget`:

```dart
/// Devuelve el nombre base saneado o null si es inválido (vacío tras trim, o
/// contiene separadores de ruta). No incluye extensión.
String? sanitizeRenameTarget(String input);
// - trim; vacío → null
// - contiene '/' o '\' → null
// - si no cambió respecto al base actual → el llamador trata como no-op
```

## 5. UI

### 5.1 Cablear el ⋮
En `video_density_feed.dart`, ambos `VideoTile` pasan `onOptions: () => showVideoOptions(context, ref, v)` en vez de `null`.

### 5.2 `VideoOptionsSheet`
`lib/ui/home/widgets/video_options_sheet.dart` — bottom sheet theme-aware (usa `Theme.of(context).colorScheme`, coherente con el resto), encabezado con el nombre del video y filas:
1. **Compartir** (icono compartir)
2. **Renombrar** (icono editar)
3. **Detalles** (icono info)
4. **Borrar** (icono borrar, texto/icono en `colorScheme.error`) — al final, separado.

Cada fila cierra la hoja y dispara la acción.

### 5.3 Renombrar
Diálogo (`AlertDialog` theme-aware) con `TextField` prefill del **nombre base** (sin extensión), un sufijo mostrando la extensión (`.mp4`) bloqueado, botón Guardar deshabilitado si `sanitizeRenameTarget` da null o el nombre no cambió. Al guardar → `controller.rename` → SnackBar de éxito/error; `cancelled` (consentimiento rechazado) → silencioso.

### 5.4 Detalles
Hoja/`AlertDialog` con filas etiqueta→valor: Nombre, Carpeta (`folder`/`path`), Tamaño (`fmtSize`), Duración (`fmtDuration`), Resolución (`${width}×${height}` si `>0`, si no "—"), Fecha (`dateAddedMs`), y la URI (seleccionable). Solo lectura.

### 5.5 Borrar
La UI **siempre** muestra su propio `AlertDialog` de confirmación antes de llamar al nativo — corto: *"¿Borrar «nombre»? Esta acción no se puede deshacer."* con Cancelar / Borrar (en `colorScheme.error`). Una sola ruta de código en Dart, sin ramificar por nivel de API. En API 30+ el sistema mostrará **además** su propio diálogo tras el `createDeleteRequest`; aceptamos esa doble confirmación como el precio de un flujo único y predecible (borrar es destructivo, un tap extra es tolerable). Tras el confirm propio: `controller.delete(v)` → `ok` → SnackBar "Video borrado"; `cancelled` (rechaza el diálogo del SO) → silencioso; `error` → SnackBar de error.

## 6. Errores y bordes

- Toda op nativa que lance → `FileOpStatus.error` → SnackBar "No se pudo completar la acción".
- `cancelled` (usuario rechaza consentimiento del SO) → silencioso, sin cambios.
- Rename a un nombre que ya existe en la carpeta → MediaStore puede fallar; se trata como `error` con SnackBar.
- Tras borrar/renombrar, el refresh del índice reordena la lista; los tiles se re-llavean por `uri` (ya lo hacen) así que no hay flash.

## 7. Unidades y límites

1. **`media_file_ops.dart`** (interfaz + tipos) — contrato de plataforma.
2. **`android_media_file_ops.dart` + Kotlin** — impl MediaStore/consentimiento.
3. **`video_actions.dart`** (`VideoActionsController` + `sanitizeRenameTarget`) — orquestación pura + efectos sobre stores/índice; testeable con fakes.
4. **`video_options_sheet.dart`** + diálogos rename/detalles/confirm-borrado — UI.
5. **`played.dart`** — gana `remove`.
6. **`media_indexer.dart` + scan** — 3 campos opcionales.

## 8. Testing

- **Puros/unit:**
  - `sanitizeRenameTarget`: vacío→null, con `/` o `\`→null, con espacios→trim, válido→ese.
  - Migración de rename: con `InMemoryResumeStore`/`InMemoryPlayedStore`, renombrar mueve resume+played de old→new y borra old (preserva segundos).
  - Limpieza de delete: elimina resume+played de la víctima.
  - `PlayedStore.remove` (Hive vía fake e InMemory).
- **Widget:**
  - `VideoOptionsSheet` muestra las 4 filas y cada una dispara su callback (con un `FakeMediaFileOps`).
  - Diálogo de rename: Guardar deshabilitado con nombre vacío / sin cambios; habilitado con cambio válido.
- **Fake:** `FakeMediaFileOps` en `test/fakes/fakes.dart` (registra llamadas, devuelve un `FileOpStatus`/`RenameOutcome` configurable).
- **Checklist en dispositivo (release, Pixel 6, API 36):**
  - ⋮ abre la hoja con las 4 acciones; nombre correcto en el encabezado.
  - Compartir → aparece el chooser del SO con el video.
  - Renombrar → consentimiento del SO → nombre cambia en la lista; el progreso de "continuar viendo" y el estado (no vuelve a "Nuevo") se conservan.
  - Borrar → confirm propio → diálogo del SO → desaparece de la lista; su entrada de "continuar viendo" desaparece.
  - Detalles → muestra resolución, tamaño, duración, ruta, fecha.
  - Cancelar el consentimiento del SO (borrar/renombrar) → no cambia nada, sin toast de error.

## 9. Restricciones globales

- Un solo acento configurable; nada de colores nuevos hardcodeados (borrar usa `colorScheme.error`; el resto, el esquema del tema).
- Patrón platform-boundary (interfaz + impl Android + provider throws-until-overridden + override en main.dart).
- Sin deps nuevas (compartir por intent nativo).
- `VideoItem` gana campos **opcionales** (cero ruptura de construcciones/tests existentes).
- No `flutter run`; build release + `adb install` al Pixel 6 (`24231FDF6006ST`) al cerrar el módulo.
- Suite completa verde.
