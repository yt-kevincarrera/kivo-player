# Kivo — Hito 4a: cimientos del panel de ajustes (diseño)

**Fecha:** 2026-07-03
**Estado:** Diseño aprobado por mockup ([panel 4a](https://claude.ai/code/artifact/faf0b579-7083-476d-8ac7-50f40afd8b7a)); arrancar directo.
**Contexto:** Hito 4 = panel de personalización completo. Principio del proyecto: *"casi todo lo que tenga un valor debe ser configurable"*. `KivoSettings` ya tiene ~37 campos persistidos vía `settingsProvider.notifier.set(copyWith(...))`, pero **no existe ninguna pantalla de ajustes**. Hito 4 se descompone en: **4a** (este — shell + toolkit + sección "General"), 4b (Reproducción y gestos), 4c (Interfaz), 4d (Reproducción avanzada), y aparte 4e (autoplay minimizado, arquitectónico). 4a es la base: los demás reutilizan su shell y sus widgets de fila.

## 1. Alcance de 4a

Entregar la infraestructura navegable + el toolkit reutilizable + **una** sección real ("General") que ejercite los widgets, más "Restablecer valores". Las secciones 4b/4c/4d **no** se construyen aquí; sus filas se insertan cuando cada una aterrice.

Fuera de 4a: el contenido de las demás secciones; re-arquitecturar el theming (el acento ya se aplica donde los componentes lo leen — ver §6).

## 2. Navegación (maestro-detalle)

- **Entrada:** un `IconButton` de engranaje (`Icons.settings`) en el `AppBar` de `LibraryScreen`, visible cuando **no** se está buscando (junto a densidad / abrir archivo). `onPressed` → `Navigator.of(context).push(settingsRoute())` (un `MaterialPageRoute` estándar, sin animación custom).
- **Pantalla raíz `SettingsScreen`** (`ConsumerWidget`): `AppBar` "Ajustes"; cuerpo scrollable con una **lista data-driven** de secciones. Cada entrada = `SettingNavRow` (icono en chip dorado + título + subtítulo + chevron) que empuja a su subpantalla.
  - En 4a la lista contiene solo las secciones **ya construidas**: **General** y **Acerca de**. 4b/4c/4d **insertan** su entrada en esta lista cuando existan (regla de la casa: no mostrar filas "próximamente" — precedente en el spec de 3b).
  - Al final, la fila **"Restablecer valores"** (roja, `#E8776B`): abre un `AlertDialog` de confirmación ("¿Restablecer todos los ajustes a sus valores por defecto?" · Cancelar / Restablecer); al confirmar → `settingsProvider.notifier.set(KivoSettings.defaults())`.
- **Subpantalla "General"** (`GeneralSettingsSection`, `ConsumerWidget` con su propio `Scaffold`+`AppBar` "General").
- **Subpantalla "Acerca de"** (`AboutSection`): nombre "Kivo", versión leída de `PackageInfo` (o constante si no hay dependencia), y una línea de crédito. Sin controles — cierra el shell y demuestra una subpantalla puramente informativa.

## 3. Toolkit de widgets reutilizables

Archivo `lib/ui/settings/widgets/setting_tiles.dart`. Todos leen/escriben vía callbacks (no acoplados a un provider concreto — la sección los cablea a `settingsProvider`). Lenguaje visual: tarjeta contenedora `0xFF182036` radio 13 sobre fondo `KivoColors.panel`; separador `rgba(255,255,255,.07)` entre filas; acento = `settingsProvider.accentColor`.

- **`SettingNavRow`** — `{IconData icon, String title, String? subtitle, VoidCallback onTap}`. Fila con chip de icono dorado + textos + chevron `›`.
- **`SettingSwitch`** — `{String title, String? subtitle, bool value, ValueChanged<bool> onChanged}`. `Switch` con `activeColor` = acento.
- **`SettingSlider`** — `{String title, double value, double min, double max, int? divisions, String Function(double) label, ValueChanged<double> onChanged}`. Muestra el valor formateado (dorado, `tabular-nums`) a la derecha del título y un `Slider` debajo.
- **`SettingStepper`** — `{String title, String? subtitle, int value, int min, int max, int step, String Function(int) label, ValueChanged<int> onChanged}`. `−` / valor / `+`; deshabilita los botones en los extremos.
- **`SettingSegmented<T>`** — `{String title, String? subtitle, List<(T value, String label)> options, T value, ValueChanged<T> onChanged}`. Chips segmentados (fondo `KivoColors.panel`/ground, el activo en dorado con texto oscuro), estilo idéntico al lenguaje segmentado existente.
- **`SettingColor`** — `{String title, int value, ValueChanged<int> onChanged}`. Fila con muestras (dots) de una paleta curada de presets (incluye el dorado por defecto `0xFFE8B84B`) — la seleccionada con anillo. Una muestra final **"Personalizado"** abre un `showModalBottomSheet` con un selector HSV por sliders (matiz/saturación/brillo, sin dependencias externas ni acceso a red) y una previa; al confirmar → `onChanged(argb)`.

4a construye y testea **todos** estos widgets (los consumen 4b/4c/4d). "General" monta en producción solo los que le aplican — `SettingSegmented`, `SettingColor`, `SettingSwitch`. `SettingSlider` y `SettingStepper` quedan construidos y cubiertos por test de widget, listos para 4b; **no** se montan en General (el grupo "Toolkit" del mockup era ilustrativo para la aprobación, no un elemento de producción).

## 4. Sección "General"

Tres controles, aplican al instante sobre `settingsProvider`:
- **Tema** — `SettingSegmented<String>` opciones `[('auto','Auto'), ('dark','Oscuro'), ('light','Claro')]` ↔ `themeMode`. Ya está cableado a `MaterialApp.themeMode` en `app.dart` — cambiar refleja el tema al instante.
- **Color de acento** — `SettingColor` ↔ `accentColor`. Presets sugeridos: dorado `0xFFE8B84B` (def), azul `0xFF5B9BE8`, rojo `0xFFE86B6B`, verde `0xFF57C08A`, morado `0xFFB77BE8`, + "Personalizado".
- **Háptica en gestos** — `SettingSwitch` ↔ `hapticsOnGestures`.

## 5. Archivos

- `lib/ui/settings/settings_route.dart` — helper `Route settingsRoute()`.
- `lib/ui/settings/settings_screen.dart` — raíz + lista de secciones + reset.
- `lib/ui/settings/sections/general_section.dart` — sección General.
- `lib/ui/settings/sections/about_section.dart` — Acerca de.
- `lib/ui/settings/widgets/setting_tiles.dart` — toolkit.
- `lib/ui/settings/widgets/color_picker_sheet.dart` — el sheet HSV de "Personalizado".
- `lib/ui/home/library_screen.dart` — añadir el engranaje al `AppBar`.

## 6. Notas de theming

- `themeMode` ya alimenta `MaterialApp` (`app.dart:23`, `themeModeFor`). 4a solo expone el control.
- `accentColor` lo leen directamente los componentes custom (tiles, overlays, seek/gesture preview) vía `ref.watch(settingsProvider).accentColor` — reactivo, así que cambiarlo se refleja de inmediato en ellos. **No** re-alambramos el `ColorScheme` global de `KivoTheme` en 4a (widgets Material genéricos siguen con su dorado de tema); propagar el acento al `ThemeData` es una posible mejora posterior, fuera de 4a.

## 7. Testing

- **Widget (`test/ui/settings/`):**
  - `settings_screen_test.dart`: la raíz lista "General" y "Acerca de"; tocar "General" navega a su subpantalla; "Restablecer valores" abre el diálogo y, al confirmar, llama `set` con los defaults (verificar un campo no-default vuelve a su default).
  - `general_section_test.dart`: cambiar el segmentado de tema persiste `themeMode`; togglear háptica persiste `hapticsOnGestures`; elegir un preset de color persiste `accentColor`.
  - `setting_tiles_test.dart`: cada widget del toolkit dispara su callback con el valor correcto (switch, slider, stepper en extremos deshabilitados, segmentado, color preset).
- **Device (Pixel 6):** engranaje abre Ajustes; navegar a General y volver; cambiar tema a Claro/Oscuro se ve al instante; cambiar acento a azul y ver los acentos de la biblioteca/tiles cambiar; háptica on/off; Restablecer devuelve todo a default (tema vuelve a Auto, acento a dorado).

## Fuera de alcance

- Contenido de las secciones 4b/4c/4d.
- Propagar `accentColor` al `ColorScheme` global (widgets Material genéricos).
- Autoplay minimizado (4e).
- Exportar/importar ajustes; perfiles.
