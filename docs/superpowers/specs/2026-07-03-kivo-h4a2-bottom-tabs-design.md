# Kivo — Hito 4a.2: navegación con barra de tabs inferior (diseño)

**Fecha:** 2026-07-03
**Estado:** Diseño aprobado por mockup ([tabs abajo](https://claude.ai/code/artifact/09ec3412-ef08-4438-b6e9-07d6db505fcc)) + respuestas; arrancar directo.
**Contexto:** El panel de ajustes (4a) se abría con un engranaje en el `AppBar` de la biblioteca. El usuario prefiere una **barra de tabs inferior** con **Videos | Ajustes**. Este sub-proyecto reemplaza la entrada por engranaje por un shell con navegación por tabs.

## 1. Comportamiento

- Barra inferior persistente con dos tabs: **Videos** (la biblioteca) y **Ajustes** (la raíz del panel). Activo en dorado (`KivoColors.gold`), inactivo atenuado. Estilo **icono + etiqueta** (mockup).
- **La barra se queda visible** al entrar a una carpeta (en Videos) o a una subsección (General/Acerca de, en Ajustes): cada tab tiene su **propio historial** (navegadores anidados). Cambiar de tab conserva dónde estabas en cada uno.
- El **reproductor a pantalla completa** cubre la barra (sin tabs durante la reproducción): se empuja en el **navigator raíz**, no en el del tab.
- El **mini-player** flota justo **encima** de la barra (dentro del shell), y sigue colapsado (`shrink`) cuando no hay reproducción minimizada.
- **Back de Android**: si el tab activo puede hacer pop (estás dentro de una carpeta/subsección), hace pop de su navegador anidado; si está en su raíz, comportamiento por defecto (salir).

## 2. Arquitectura

- **`HomeShell`** (`lib/ui/home/home_shell.dart`, `ConsumerStatefulWidget`) = nuevo `home:` de la app.
  - Estado: `int _index` (tab activo) + dos `GlobalKey<NavigatorState>` (`_videosNav`, `_settingsNav`).
  - `Scaffold`:
    - `body: Column([ Expanded(IndexedStack(index: _index, children: [_tabNavigator(_videosNav, LibraryScreen), _tabNavigator(_settingsNav, SettingsScreen)])), MiniPlayerBar() ])` — el mini-player como fila sobre la barra (colapsa a cero cuando no aplica).
    - `bottomNavigationBar: _BottomTabBar(index: _index, onTap: (i) => setState(...))`.
  - `_tabNavigator(key, rootScreen)` = `Navigator(key: key, onGenerateRoute: (s) => MaterialPageRoute(builder: (_) => rootScreen))`.
  - `PopScope(canPop: false, onPopInvokedWithResult:)` — enruta el back al navegador del tab activo (`key.currentState!.maybePop()`); si ese no pudo hacer pop, permite salir (pop del root). Implementación: `canPop` dinámico según `!(_activeKey.currentState?.canPop() ?? false)`.
- **`_BottomTabBar`** (privado en `home_shell.dart`): fila de 2 ítems (icono + etiqueta), activo dorado, inactivo `onSurfaceVariant`, borde superior `outlineVariant`, fondo `scaffoldBackgroundColor`, respeta safe-area inferior. Tema-aware.
- **`lib/app.dart`**: `home: const HomeShell()`. **Quitar** el `builder:` que montaba `MiniPlayerBar` a nivel de app (ahora vive en el shell). El mini-player ya no se superpone porque las carpetas se empujan en el navegador anidado (bajo el shell).
- **Empuje del reproductor al raíz:** en `library_screen.dart` (`_open`, `_openPath`) y `folder_screen.dart` (`_open`), cambiar `Navigator.of(context).push(playerRoute())` → `Navigator.of(context, rootNavigator: true).push(playerRoute())`. Así el reproductor cubre la barra. El mini-player ya expande con `kivoNavigatorKey` (raíz) — sin cambios.
- **Empuje de carpetas/subsecciones NO cambia:** `Navigator.of(context).push(...)` resuelve al navegador anidado del tab → la barra persiste. (Aplica a `library_screen` `onOpenFolder`, `settings_screen` filas de sección.)

## 3. Quitar la entrada por engranaje

- `library_screen.dart`: eliminar el `IconButton` de 'Ajustes' del `AppBar` y el `import '../settings/settings_route.dart'`.
- Eliminar `lib/ui/settings/settings_route.dart` (queda sin uso; el tab monta `SettingsScreen` directo) y su test `test/ui/home/library_settings_entry_test.dart`.

## 4. Costo aceptado (Hero de apertura)

El reproductor se empuja en el raíz mientras el tile vive en el navegador anidado; los Heroes solo animan dentro de un mismo `Navigator`, así que la **animación Hero de apertura** (tile → reproductor) deja de dispararse: la apertura queda como el `FadeTransition` de `playerRoute` (240 ms). El cierre ya no usaba Hero (minimiza con el gesto/fade). Aceptado como costo del cambio a tabs; recuperable después con un shuttle custom si se desea.

## 5. Archivos

- Crear: `lib/ui/home/home_shell.dart`.
- Modificar: `lib/app.dart` (home + quitar builder), `lib/ui/home/library_screen.dart` (quitar engranaje; player push→root), `lib/ui/home/folder_screen.dart` (player push→root).
- Eliminar: `lib/ui/settings/settings_route.dart`, `test/ui/home/library_settings_entry_test.dart`.
- Test: `test/ui/home/home_shell_test.dart`.

## 6. Testing

- **Widget (`home_shell_test.dart`):** arranca en Videos (LibraryScreen visible, barra presente con "Videos"/"Ajustes"); tocar "Ajustes" muestra `SettingsScreen` (aparece "Ajustes"/secciones); tocar "Videos" vuelve; el estado del tab se conserva (IndexedStack). Overrides de providers como en `library_screen_test.dart` (mediaIndexer, playedStore, settingsService).
- **Device (Pixel 6):** barra abajo con Videos|Ajustes (activo dorado); entrar a una carpeta mantiene la barra; entrar a General mantiene la barra; abrir un video **cubre** la barra; al minimizar, el mini-player aparece sobre la barra; back de Android sale de la carpeta/subsección sin cerrar la app; cambiar de tab conserva la posición de cada uno.

## Fuera de alcance

- Recuperar el Hero de apertura con un shuttle custom (posible follow-up).
- Un tercer tab / reordenar secciones.
- Persistir el tab activo entre sesiones.
