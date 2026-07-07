# Kivo — Selección múltiple en la biblioteca (long-press + batch)

**Fecha:** 2026-07-07
**Estado:** Aprobado para plan
**Alcance:** Selección múltiple en la biblioteca: long-press en un tile entra en modo selección; en ese modo cada tile y cada cabecera de día muestran checkbox; una barra contextual ofrece Compartir y Borrar en lote. Sub-proyecto B (B sigue a A = borrado silencioso, ya hecho). Vault/ocultar = futuro.

---

## Contexto

- `VideoTile` (`lib/ui/home/widgets/video_tile.dart`) es un `ConsumerStatefulWidget` con `onTap(Rect? origin)` (abre, con Hero) y `onOptions` (⋮). **No** tiene long-press ni estado de selección.
- El feed compartido `VideoDensityFeed` (`lib/ui/home/widgets/video_density_feed.dart`) lo usan la biblioteca ("Todo", agrupado por día vía `groupByDay` → `DaySection{label, items}`) y `FolderScreen` (plano, `groupByDate: false`, una sola `DaySection` con label vacío). Las cabeceras de día se dibujan como un `Row` (barra de acento + `Text(s.label)`) en un `SliverToBoxAdapter`. La tira "Continuar viendo" (`ContinueRow`) es un sliver aparte.
- `library_screen.dart` y `folder_screen.dart` son `Scaffold` con `AppBar` propio; la biblioteca ya intercambia el contenido del AppBar según modo búsqueda (`AnimatedSwitcher`).
- `VideoActionsController` (`lib/player/library/video_actions.dart`) ya hace delete/rename/share individuales + efectos (limpieza/migración de llaves por nombre + `_refreshLibrary`). `MediaFileOps` (`lib/platform/interfaces/media_file_ops.dart`) tiene `delete`/`rename`/`share`; el nativo (`kivo/media` en `MainActivity.kt`) ya ramifica por `Environment.isExternalStorageManager()` (silencioso) vs consentimiento. `maybeOfferAllFilesAccess` (`video_options_sheet.dart`) ofrece el permiso una vez.

---

## 1. Estado de selección

`lib/ui/home/state/library_selection.dart`:

```dart
/// Selección múltiple de la biblioteca: el set de URIs seleccionadas.
/// **Modo selección activo ⇔ el set no está vacío.** Deseleccionar el último
/// item sale del modo.
class LibrarySelectionNotifier extends StateNotifier<Set<String>> {
  LibrarySelectionNotifier() : super(const {});

  bool isSelected(String uri) => state.contains(uri);
  bool get active => state.isNotEmpty;

  void toggle(String uri) {
    final next = Set<String>.of(state);
    next.contains(uri) ? next.remove(uri) : next.add(uri);
    state = next;
  }

  /// Alterna un grupo (un día): si TODOS ya están seleccionados los quita;
  /// si no, agrega los que falten.
  void toggleAll(Iterable<String> uris) {
    final all = uris.toSet();
    final next = Set<String>.of(state);
    if (all.every(next.contains)) {
      next.removeAll(all);
    } else {
      next.addAll(all);
    }
    state = next;
  }

  /// Selecciona exactamente [uris] (para "Seleccionar todo" con la lista visible).
  void selectAll(Iterable<String> uris) => state = uris.toSet();

  void clear() => state = const {};
}

final librarySelectionProvider =
    StateNotifierProvider<LibrarySelectionNotifier, Set<String>>(
        (ref) => LibrarySelectionNotifier());
```

Helper puro para el tri-estado de una cabecera de día:

```dart
enum GroupCheckState { none, some, all }

GroupCheckState groupCheckState(Iterable<String> groupUris, Set<String> selected) {
  final g = groupUris.toSet();
  if (g.isEmpty) return GroupCheckState.none;
  final n = g.where(selected.contains).length;
  if (n == 0) return GroupCheckState.none;
  if (n == g.length) return GroupCheckState.all;
  return GroupCheckState.some;
}
```

## 2. `VideoTile`: long-press + estado seleccionado

Nuevos parámetros:
- `final VoidCallback? onLongPress;`
- `final bool selected;` (default `false`)
- `final bool selecting;` (default `false`) — si el modo selección está activo (para que el tap alterne en vez de abrir; lo decide el feed, pero el tile lo necesita para el `PressBounce`/semántica).

Comportamiento:
- `PressBounce` gana `onLongPress: widget.onLongPress`.
- Cuando `selected`, superponer (en el `Stack` de la miniatura, ambos layouts) un velo semitransparente + un check circular en color de acento (arriba-derecha en cover, o a la izquierda en list-row). Theme-aware (`onAccent(accent)` para el tick). Cuando `selecting` pero no `selected`, mostrar un círculo vacío (outline) como afordancia.
- El tile NO decide abrir vs alternar; sigue exponiendo `onTap(Rect?)` y `onLongPress()`. El feed cablea qué hacen.

## 3. Feed: cablear selección + checkbox de día

En `_VideoDensityFeedState.build`:
- `final selected = ref.watch(librarySelectionProvider);`
- `final selecting = selected.isNotEmpty;`
- `final sel = ref.read(librarySelectionProvider.notifier);`
- Cada `VideoTile` (cover + list): 
  - `selected: selected.contains(v.uri)`, `selecting: selecting`
  - `onLongPress: () => sel.toggle(v.uri)`
  - `onTap: (origin) => selecting ? sel.toggle(v.uri) : widget.onOpen(v, widget.videos, origin)`
- **Cabecera de día** (solo cuando `selecting` y `s.label.isNotEmpty`): añadir al `Row` de la cabecera, a la izquierda, un checkbox tri-estado según `groupCheckState(s.items.map((v)=>v.uri), selected)`:
  - `all` → check lleno (acento); `some` → guion/indeterminado; `none` → outline.
  - `onTap` → `sel.toggleAll(s.items.map((v) => v.uri))`.
  - Fuera de modo selección, la cabecera se ve como hoy (sin checkbox).
- La tira `ContinueRow` **no** participa en la selección (sus tiles siguen solo-abrir; se le pasa el comportamiento normal). Nota: `ContinueRow` construye sus propios `VideoTile` con los nuevos defaults (`selected:false, selecting:false, onLongPress:null`), así que no cambia.

## 4. Barra contextual

`lib/ui/home/widgets/selection_app_bar.dart` — `SelectionAppBar implements PreferredSizeWidget` (`ConsumerWidget`), usado en el `appBar:` de `library_screen` y `folder_screen` cuando `ref.watch(librarySelectionProvider).isNotEmpty`:
- **leading**: X → `sel.clear()`.
- **title**: "N seleccionados" (N = `selected.length`).
- **actions**:
  - **Seleccionar todo** (icono `select_all`) → `sel.selectAll(allVisibleUris)`. Cada pantalla le pasa su lista visible (biblioteca: `filtered`; carpeta: `vids`). (Requiere un método `selectAll(Iterable<String>)` en el notifier: `state = uris.toSet()`.)
  - **Compartir** (`share`) → `controller.shareMany(selectedVideos)`.
  - **Borrar** (`delete`, color `error`) → flujo de borrado batch (§5).
- `PreferredSize`: altura estándar de AppBar (`kToolbarHeight`).

Integración por pantalla: `appBar: sel.isNotEmpty ? SelectionAppBar(allVisible: <lista>) : <appBar normal>`. La lista de "seleccionados" se resuelve mapeando las URIs del set contra la lista visible de esa pantalla.

**Back del sistema en modo selección** → limpiar, no salir de la pantalla. En `library_screen`/`folder_screen`, envolver con `PopScope(canPop: !selecting, onPopInvokedWithResult: (didPop,_){ if(!didPop) sel.clear(); })`. (Ojo: la biblioteca vive en un tab con su propio navigator; el `PopScope` intercepta antes que la lógica de tabs — verificar en implementación que no rompe el back de tabs cuando NO hay selección: `canPop` true cuando no hay selección deja pasar el back normal.)

## 5. Acciones batch

### 5.1 `MediaFileOps` + nativo
Nuevos métodos en la interfaz:
```dart
Future<FileOpStatus> deleteMany(List<String> uris);
Future<void> shareMany(List<String> uris);
```
`AndroidMediaFileOps`: `deleteMany` → `invokeMethod<String>('deleteMany', {'uris': uris})` → `_status`; `shareMany` → `invokeMethod<void>('shareMany', {'uris': uris})`.

Nativo (`kivo/media`):
- **`deleteMany`**: parsear las uris. Si `Environment.isExternalStorageManager()` → `contentResolver.delete` en bucle → `"ok"`. Si no y API 30+ → **un solo** `MediaStore.createDeleteRequest(resolver, uris)` → `startIntentSenderForResult(REQ_DELETE)` → `onActivityResult` responde `ok`/`cancelled` (reutiliza `pendingFileOpResult`). API < 30 → bucle `resolver.delete`. (Un único diálogo del sistema para todo el lote.)
- **`shareMany`**: `Intent(ACTION_SEND_MULTIPLE)`, `type="video/*"`, `putParcelableArrayListExtra(EXTRA_STREAM, ArrayList<Uri>)`, `FLAG_GRANT_READ_URI_PERMISSION`, `startActivity(createChooser)`.

### 5.2 `VideoActionsController`
```dart
Future<FileOpStatus> deleteMany(List<VideoItem> videos);
Future<void> shareMany(List<VideoItem> videos);
```
- `deleteMany`: `ops.deleteMany(uris)`; si `ok` → por cada video: `resume.clear(name)` + `played.remove(name)`; luego un `_refreshLibrary()`. Devuelve el status.
- `shareMany`: `ops.shareMany(uris)`.

### 5.3 UI del borrado batch (en `SelectionAppBar` o un helper `runBatchDelete(context, ref, videos)`)
- 1 `AlertDialog`: "¿Borrar N videos? Esta acción no se puede deshacer." (Borrar en `error`).
- Antes de llamar al controlador: `await maybeOfferAllFilesAccess(context, ref)` (reutilizado) para no encadenar diálogos.
- `final status = await controller.deleteMany(videos);` → `ok`: SnackBar "N videos borrados" + `sel.clear()`; `error`: SnackBar de error; `cancelled`: silencioso.
- Compartir: `await controller.shareMany(videos); sel.clear();`.
- Guardas `context.mounted` tras cada await; `messenger` pre-capturado.

## 6. Unidades y límites

1. **`library_selection.dart`** — estado + `groupCheckState` (puro).
2. **`video_tile.dart`** — long-press + overlay de selección.
3. **`video_density_feed.dart`** — cablear tap/long-press + checkbox de día.
4. **`selection_app_bar.dart`** — barra contextual + acciones.
5. **`video_actions.dart`** + **`media_file_ops.dart`** + **`MainActivity.kt`** — `deleteMany`/`shareMany`.
6. **`library_screen.dart` / `folder_screen.dart`** — AppBar condicional + `PopScope`.

## 7. Testing

- **Unit:**
  - `LibrarySelectionNotifier`: `toggle` (add/remove + sale al vaciar), `toggleAll` (día completo: agrega faltantes / quita si todos), `selectAll`, `clear`, `isSelected`, `active`.
  - `groupCheckState`: none/some/all + grupo vacío.
  - `VideoActionsController.deleteMany`: con fakes, borra todo, limpia resume+played de cada nombre, `ok` → refresh; `cancelled`/`error` → no toca stores. `shareMany` pasa las uris.
- **Widget:**
  - Feed: long-press en un tile entra en modo (aparecen checkboxes) y tap alterna; el checkbox de cabecera de día marca todo el día (tri-estado).
  - `SelectionAppBar`: muestra "N seleccionados", y X limpia; Seleccionar todo llena; Borrar/Compartir disparan.
- **Fake:** extender `FakeMediaFileOps` con `deletedManyUris`/`sharedManyUris` + `deleteManyResult`.
- **Checklist en dispositivo (release, Pixel 6):**
  - Long-press → modo selección (checkbox en tiles + cabeceras de día); tap alterna; deseleccionar el último sale del modo.
  - Checkbox de un día marca/desmarca todo ese día (tri-estado correcto con selección parcial).
  - Barra: "N seleccionados", Seleccionar todo, X y back del sistema limpian sin salir de la pantalla.
  - Borrar N: 1 confirm → (con acceso total) sin diálogo del SO / (sin él) un solo diálogo del sistema para todo el lote → desaparecen; sus entradas de "continuar viendo" también; sale del modo.
  - Compartir N → chooser con múltiples videos.
  - En una carpeta (feed plano, sin cabeceras de día): selección de tiles y batch funcionan; no hay checkbox de día.

## 8. Restricciones globales

- Un solo acento configurable; nada de colores nuevos hardcodeados (Borrar/`error`, check en acento vía `onAccent`).
- Patrón platform-boundary; sin deps nuevas.
- La selección vive en un provider (sin estado global fuera de Riverpod).
- Reutiliza el borrado silencioso/offer de A (no re-implementa permisos).
- No `flutter run`; build release + `adb install` al Pixel 6 (`24231FDF6006ST`) al cerrar el módulo.
- Suite completa verde.
