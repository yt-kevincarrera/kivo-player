# Kivo — Unificar el color en el acento + refinamientos de theming (diseño)

**Fecha:** 2026-07-03
**Estado:** Diseño aprobado (enfoque + respuestas del usuario); auditoría de hardcodes completa. Arrancar directo.
**Contexto:** Tras 4a, cambiar el color de acento dejaba muchas partes en el dorado/azul original. El usuario quiere **un solo color** (el acento, default dorado; retirar el azul), que el acento se propague a **todos** los controles/indicadores, más fixes concretos del reproductor y un ajuste de estilo de iconos. Base: auditoría en `.superpowers` (74 hardcodes de `gold`, 3 de `blue`, 5 sitios de "tinta sobre acento").

## 1. Decisiones (confirmadas)

- **Un solo color = el acento.** Retirar `KivoColors.blue` como color de marca. Default del acento = dorado `0xFFE8B84B` (sin cambios en el default). Cambiar el acento recolorea **absolutamente todo**.
- **Estilo de iconos duotono/plano** = preferencia **global** (afecta biblioteca, ajustes y reproductor). Default: duotono.
- Superficies oscuras deliberadas (paneles de sheets, fondos de tarjetas del reproductor) **no** cambian. Los swatches de color de subtítulos y la paleta de presets del acento **no** cambian (son paletas fijas de elección).

## 2. Theme derivado del acento (palanca principal)

`lib/core/theme/kivo_theme.dart`:
- `_build({required Brightness brightness, required Color accent, ...})`: `ColorScheme.fromSeed(seedColor: accent, brightness: ...)` y `.copyWith(primary: accent, secondary: accent, onPrimary: onAccent(accent), onSecondary: onAccent(accent), surface: ..., onSurface: ..., onSurfaceVariant: ...)`. Se retira `seedColor: KivoColors.blue` y `primary: KivoColors.blue`.
- `KivoTheme.dark(Color accent)` / `light(Color accent)` pasan a **recibir** el acento.
- Nuevo helper **`Color onAccent(Color accent)`** (en `kivo_theme.dart`): `accent.computeLuminance() > 0.5 ? const Color(0xFF1A1205) : Colors.white` — el color de texto/icono legible sobre un relleno del acento. Generaliza el `isLight` que hoy vive en `track_picker.dart`.
- `KivoColors.blue` se elimina de la clase (ya sin usos tras §4). `KivoColors.gold` se conserva solo como el valor por defecto del preset (referenciado en `kivo_settings.dart` defaults y en `kAccentPresets`).

`lib/app.dart`:
- `KivoApp` observa también el acento: `final accent = Color(ref.watch(settingsProvider.select((s) => s.accentColor)));` y `theme: KivoTheme.light(accent)`, `darkTheme: KivoTheme.dark(accent)`. Cambiar el acento reconstruye el `MaterialApp` → todos los `cs.secondary`/`cs.primary` se recolorean.

**Consecuencia (gratis):** todos los consumidores actuales de `cs.secondary` (los `SettingTiles`, la barra de tabs `home_shell.dart:103`, el eyebrow de secciones, el color picker "Aplicar") pasan a seguir el acento sin tocarlos, y con `onSecondary` ahora correcto.

## 3. Helper "on-accent" + arreglo de "tinta sobre acento"

Sustituir cada `Color(0xFF231705)` horneado (texto/icono oscuro sobre relleno del acento) por `onAccent(accent)`:
- `track_picker.dart:226` (label de tab activa), `sleep_timer_panel.dart:511` (botón primario), `sleep_warning_toast.dart:134` ("Extender"), `autoplay_overlay.dart:176` ("Reproducir"), `queue_strip.dart:166` ("AHORA").
- También los "texto blanco sobre relleno de marca" que dependían de que el color fuera oscuro: chips activos de `library_screen.dart` y badge "Nuevo" de `video_tile.dart` → usar `onAccent(accent)` en vez de `Colors.white` fijo.
- Eliminar el `isLight` local de `track_picker.dart` y usar el helper compartido.

## 4. Barrido de hardcodes de marca → acento

Rutear **todo** `KivoColors.gold` que sea activo/indicador a `Color(ref.watch(settingsProvider).accentColor)` (varios de estos archivos ya calculan `accent` local; los dorados restantes usan esa misma variable). Retirar `KivoColors.blue` (→ acento). Archivos y conteo (de la auditoría):

- **Home:** `library_screen.dart` (chips Todo/Carpetas + "No vistos", 2 sitios `blue`), `video_tile.dart` ("Nuevo" badge `blue`), `folder_grid.dart` (pill "N vids", 3 gold), `mini_player_bar.dart` (barra de progreso, 1 gold).
- **Reproductor — paneles:** `track_picker.dart` (~15), `speed_panel.dart` (~9), `sleep_timer_panel.dart` (~17), `sleep_warning_toast.dart` (~5).
- **Reproductor — overlays:** `ab_loop_chip.dart` (~8), `ab_range_layer.dart` (1 — pintura del rango A/B en la seek bar), `autoplay_overlay.dart` (~6), `audio_only_view.dart` (~5), `queue_strip.dart` (~3).

**No tocar** (superficies fijas, enumeradas en la auditoría): `KivoColors.panel`/`ink`, `0xFF182036`, `0xFF0C1120`, `0xFF1C2A44`, gradientes de fondo, `Color.fromRGBO(10,14,26,...)`, paletas de swatches de subtítulos, `kAccentPresets`, y los `Colors.white*` de overlays sobre scrim oscuro (NO cambiarlos a `cs.onSurface`, que voltearía en tema claro).

## 5. Fixes concretos del reproductor

`lib/ui/player/controls/center_controls.dart`:
- **Anillo del play/pausa** (L107-108): `BorderSide(color: Colors.white, width: 3)` (antes acento, width 2). Siempre blanco.
- **Label de segundos del skip** (L69-71): `color: Colors.white` + `shadows` (sombra negra suave) para legibilidad sobre video claro.

`lib/ui/player/gestures/ripple_overlay.dart`:
- **Label "±Ns"** (L82-86): `color: Colors.white` + `shadows` (halo oscuro), ya que el círculo de fondo es blanco. También el `KivoIcon` del chevron se queda blanco (ya lo está). Con la sombra queda legible sobre el blob blanco y sobre cualquier fotograma.

## 6. Ajuste nuevo: estilo de iconos (duotono | plano)

`lib/core/settings/kivo_settings.dart`: nuevo campo **`String iconStyle`** (`'duotone'` | `'flat'`, default `'duotone'`), en los 6 puntos de inserción (field, ctor, defaults, copyWith param+body, toMap, fromMap).

`lib/core/icons/kivo_icons.dart` (`KivoIcon.build`): si `iconStyle == 'flat'`, la sustitución del token `__ACCENT__` usa `color` (el `currentColor` base, normalmente blanco) en vez del acento → iconos monocromos. Duotono = comportamiento actual. Un `accent:` explícito sigue teniendo prioridad solo en duotono.

`lib/ui/settings/sections/general_section.dart`: añadir en "Apariencia" un `SettingSegmented<String>` **"Iconos"** con opciones `[('duotone','Duotono'), ('flat','Plano')]` ↔ `iconStyle`.

## 7. Testing

- **Unit (`test/core/theme/`):** `onAccent` devuelve oscuro sobre acento claro (gold) y blanco sobre acento oscuro (p.ej. `0xFF102040`); `KivoTheme.dark(accent).colorScheme.secondary == accent` y `.primary == accent`.
- **Widget:** `KivoIcon` en modo `flat` no inyecta el acento (el SVG no contiene el hex del acento; contiene el `color` base) y en `duotone` sí — con un `ProviderScope` que fija `iconStyle`. `SettingSegmented` de iconos persiste `iconStyle`. Un widget representativo (p.ej. `speed_panel` chip activo o `queue_strip` "AHORA") toma el acento overrideado y su texto usa `onAccent`.
- **Settings service:** `iconStyle` sobrevive round-trip (6 puntos) — extender `settings_service_test.dart`.
- **Regresión:** suite completa verde; `flutter analyze` limpio.
- **Device (Pixel 6):** cambiar el acento a azul/rojo/oscuro y verificar que **todo** se recolorea (chips de biblioteca, tabs, seek bar, paneles de velocidad/sleep/tracks, A-B, autoplay, cola, mini-player, HUD); con un acento oscuro el texto sobre relleno sigue legible (onAccent); anillo del play blanco y grueso; segundos del skip y del ripple visibles sobre video claro; Duotono↔Plano cambia todos los iconos; tema claro sigue legible (superficies fijas intactas).

## 8. Descomposición del plan (tareas)

1. Theme derivado del acento + `onAccent` helper + `app.dart` reactivo + retirar `KivoColors.blue` de la clase (tras mover sus usos). Tests de tema.
2. Home: retirar `blue` y rutear gold al acento (`library_screen`, `video_tile`, `folder_grid`, `mini_player_bar`), con `onAccent` para textos sobre relleno.
3. Sweep paneles del reproductor (`track_picker`, `speed_panel`, `sleep_timer_panel`, `sleep_warning_toast`) → acento + `onAccent`; eliminar `isLight` local.
4. Sweep overlays del reproductor (`ab_loop_chip`, `ab_range_layer`, `autoplay_overlay`, `audio_only_view`, `queue_strip`) → acento + `onAccent`.
5. Fixes de control (`center_controls` anillo blanco+grueso, segundos blancos+sombra; `ripple_overlay` segundos blancos+sombra).
6. Ajuste `iconStyle` (kivo_settings 6 puntos, `KivoIcon` flat, `general_section` segmentado) + tests.

## Fuera de alcance

- Rediseñar la paleta de swatches del acento o de subtítulos.
- Recuperar el Hero de apertura (follow-up separado).
- Cambiar superficies/tema base más allá de derivar del acento.
- 4b (Reproducción y gestos) — el siguiente sub-proyecto tras esto.
