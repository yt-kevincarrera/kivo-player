# Kivo 2c — Búsqueda, orden y filtro "No vistos" (Diseño)

**Fecha:** 2026-07-01
**Estado:** Diseño aprobado.
**Contexto:** Hito 2 / bloque 2c — último pendiente del roadmap de biblioteca. Activa los íconos diferidos de la barra superior (búsqueda, orden) prometidos desde el rediseño original, y añade un filtro "No vistos" reutilizando el tracking de reproducidos ya existente.

## 1. Alcance

- **Búsqueda:** global (busca en TODOS los videos indexados, sin importar carpeta), por nombre de archivo **o** nombre de carpeta. Resultado: lista plana de videos.
- **Orden:** 7 opciones (Reciente · Nombre A-Z · Nombre Z-A · Duración larga primero · Duración corta primero · Tamaño pesado primero · Tamaño liviano primero). Solo aplica a la pestaña "Todo" y a los resultados de búsqueda — no a "Carpetas".
- **Filtro "No vistos":** toggle (no una pestaña) que muestra solo videos nunca reproducidos. Aplica a "Todo" y a la búsqueda; no a "Carpetas".
- Búsqueda, orden y "No vistos" **componen entre sí** (se pueden combinar).
- Fuera de alcance: orden/filtro dentro de una carpeta específica, filtro "en progreso", historial/sugerencias de búsqueda.

## 2. Estado

Nuevo archivo `lib/ui/home/state/library_filter_state.dart`:

```dart
enum LibrarySort { recent, nameAsc, nameDesc, durationAsc, durationDesc, sizeAsc, sizeDesc }

final librarySearchActiveProvider = StateProvider<bool>((ref) => false);
final librarySearchQueryProvider = StateProvider<String>((ref) => '');
final libraryUnwatchedOnlyProvider = StateProvider<bool>((ref) => false); // no persistido
```

`LibrarySort` se persiste como parte de `KivoSettings`, siguiendo el mismo patrón que `themeMode` (que guarda `'auto'|'light'|'dark'` como `String`, no un enum directo — evita fricción de serialización): nuevo campo `final String librarySort;` (valores: `'recent'|'nameAsc'|'nameDesc'|'durationAsc'|'durationDesc'|'sizeAsc'|'sizeDesc'`, default `'recent'`), con su entrada en `copyWith`/`toMap`/`fromMap` idéntica a como está `themeMode` hoy. El enum `LibrarySort` (capa de UI) tiene un helper `librarySortFor(String)`/`.name` para convertir, igual que `themeModeFor(String)` ya existe para `themeMode`. `libraryUnwatchedOnlyProvider`/`librarySearchQueryProvider`/`librarySearchActiveProvider` NO se persisten — se resetean cada apertura de la app, igual que una búsqueda normal.

## 3. Lógica pura compartida

Nuevo archivo `lib/player/library/library_filter.dart`:

```dart
List<VideoItem> applyLibraryFilters(
  List<VideoItem> videos, {
  String query = '',
  LibrarySort sort = LibrarySort.recent,
  bool unwatchedOnly = false,
  Set<String> playedKeys = const {},
}) {
  var out = videos;
  if (query.trim().isNotEmpty) {
    final q = query.trim().toLowerCase();
    out = out.where((v) =>
        v.name.toLowerCase().contains(q) || v.folder.toLowerCase().contains(q)).toList();
  }
  if (unwatchedOnly) {
    out = out.where((v) => !playedKeys.contains(v.name)).toList();
  }
  out = [...out];
  switch (sort) {
    case LibrarySort.recent:
      out.sort((a, b) => b.dateAddedMs.compareTo(a.dateAddedMs));
    case LibrarySort.nameAsc:
      out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    case LibrarySort.nameDesc:
      out.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    case LibrarySort.durationAsc:
      out.sort((a, b) => a.durationMs.compareTo(b.durationMs));
    case LibrarySort.durationDesc:
      out.sort((a, b) => b.durationMs.compareTo(a.durationMs));
    case LibrarySort.sizeAsc:
      out.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
    case LibrarySort.sizeDesc:
      out.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
  }
  return out;
}
```

Esta función es la única fuente de verdad para "qué videos se muestran y en qué orden" en la pestaña Todo y en los resultados de búsqueda. `VideoDensityFeed` sigue recibiendo la lista YA filtrada/ordenada — no necesita saber nada de búsqueda/orden/filtro.

## 4. Agrupado por fecha condicional

`VideoDensityFeed` ya soporta `groupByDate: bool`. `LibraryScreen` decide su valor: `groupByDate: sort == LibrarySort.recent` — con "Reciente" se agrupa por día (Hoy/Ayer/…, comportamiento actual); con cualquier otro orden, lista plana (`groupByDate: false`, sin encabezados). Esto no requiere cambios en `VideoDensityFeed` — ya tiene el parámetro.

## 5. Búsqueda — UI

- Ícono de lupa en el `AppBar.actions`, siempre visible (ambas pestañas).
- Al tocarlo: `librarySearchActiveProvider = true`. El `AppBar.title` se reemplaza por un `TextField` (autofocus, hint "Buscar videos o carpetas") que escribe en `librarySearchQueryProvider` en cada cambio. Una `IconButton` (X) al final cierra la búsqueda: `librarySearchActiveProvider = false; librarySearchQueryProvider = ''`.
- Cuando `librarySearchActiveProvider == true`, el `body` de `LibraryScreen` reemplaza los chips Todo|Carpetas + `PageView` por:
  - Un chip suelto "No vistos" (mismo toggle que en Todo).
  - `VideoDensityFeed(videos: applyLibraryFilters(allVideos, query: ..., sort: ..., unwatchedOnly: ..., playedKeys: ...), groupByDate: sort == LibrarySort.recent, showContinueRow: false)`.
  - Si la lista resultante está vacía y `query` no está vacío: `Center(child: Text('No se encontraron videos para "$query"'))` en vez del feed.
- El ícono de orden sigue visible/activo durante la búsqueda (compone).

## 6. Orden — UI

- Ícono en `AppBar.actions` (p. ej. un ícono de "ordenar"), visible cuando la pestaña activa es "Todo" **o** cuando se está buscando; oculto cuando la pestaña activa es "Carpetas" (y no se está buscando).
- Al tocarlo, `PopupMenuButton` con las 7 opciones (etiquetas: "Más reciente", "Nombre A-Z", "Nombre Z-A", "Duración: más larga", "Duración: más corta", "Tamaño: más pesado", "Tamaño: más liviano"), marcando con un check la opción activa (`librarySortProvider`/`settings.librarySort`). Seleccionar una opción actualiza `settings.librarySort` (persistido).

## 7. Filtro "No vistos" — UI

- Chip de estilo distinto al de Todo/Carpetas (para señalar que es un toggle, no una pestaña) — por ejemplo con un ícono de check/ojo-tachado y fondo que cambia de `surfaceContainerHighest` a `KivoColors.blue` cuando está activo (mismo lenguaje visual que los chips existentes).
- Visible: junto a Todo|Carpetas cuando la pestaña activa es "Todo"; también visible (solo) durante la búsqueda. Oculto en la pestaña "Carpetas".
- Alterna `libraryUnwatchedOnlyProvider`.

## 8. Archivos

```
lib/core/settings/kivo_settings.dart        (+ librarySort field/copyWith/toMap/fromMap, default LibrarySort.recent)
lib/ui/home/state/library_filter_state.dart (nuevo: LibrarySort enum, librarySearchActiveProvider, librarySearchQueryProvider, libraryUnwatchedOnlyProvider)
lib/player/library/library_filter.dart      (nuevo: applyLibraryFilters — pura, testeada)
lib/ui/home/library_screen.dart             (AppBar: íconos búsqueda+orden; body: campo de búsqueda / chip No vistos / feed filtrado)
```

## 9. Testing

- **Puro:** `applyLibraryFilters` — cada orden produce la secuencia esperada; `query` filtra por nombre y por carpeta (insensible a mayúsculas); `unwatchedOnly` excluye reproducidos; combinaciones de los tres. `KivoSettings.librarySort` round-trip (toMap/fromMap) + default.
- **Widget:** tocar la lupa muestra el campo y oculta el título; escribir filtra el feed a resultados que coincidan; X limpia y cierra; el ícono de orden abre el menú y cambiar la opción reordena el feed (y quita/pone los encabezados de fecha según corresponda); el chip "No vistos" alterna el filtro y desaparece en la pestaña Carpetas; sin resultados muestra el mensaje vacío.
- **Device:** verificar que buscar por nombre de carpeta encuentra el video correcto; que cambiar de orden se siente instantáneo; que "No vistos" + búsqueda combinados dan el resultado esperado; que el ícono de orden desaparece/reaparece correctamente al cambiar entre Todo/Carpetas.
