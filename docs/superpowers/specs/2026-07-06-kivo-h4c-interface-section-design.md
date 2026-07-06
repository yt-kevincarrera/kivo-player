# Kivo — Hito 4c: sección "Interfaz" (diseño)

**Fecha:** 2026-07-06
**Estado:** Diseño aprobado por el usuario; arrancar directo.
**Contexto:** El shell (4a) y el toolkit (`SettingSwitch/Slider/Stepper/Segmented`, `SettingsCard`, `SettingNavRow`) ya están. 4c llena la sección **Interfaz** cableando campos de UI de `KivoSettings` que ya existen (aplican al instante). Dos campos con >2 opciones necesitan controles nuevos: el **contenido** del info-overlay (lista seleccionable) y su **esquina** (selector visual 2x2). Tema/acento/iconos ya viven en General (4a).

## 1. Decisiones (confirmadas)

- **Contenido del info-overlay:** lista seleccionable con los **3 modos implementados** — `name_time` "Nombre y tiempo", `name` "Solo nombre", `remaining` "Tiempo restante". El 4º modo del campo, **`clock`, NO se expone** (no está implementado en `info_overlay.dart`; exponerlo confundiría, como el `holdRightMin` de 4b). Queda fuera de alcance implementarlo aquí.
- **Esquina del info-overlay:** un **selector visual 2x2** (mini rectángulo con 4 esquinas tocables).
- **Aspecto por defecto:** solo `fit`/`fill`/`stretch` (los forzados 16:9/4:3/original siguen fuera de alcance).

## 2. Widgets nuevos (reutilizables)

**`SettingChoice<T>`** (`lib/ui/settings/widgets/setting_choice.dart`) — lista tipo radio.
`SettingChoice<T>({required String title, String? subtitle, required List<(T, String)> options, required T value, required ValueChanged<T> onChanged})`. Título + una fila por opción (etiqueta + un check/radio dorado cuando está seleccionada); tocar una fila la selecciona. Tema-aware. (Reutilizable: 4d la usará para "Continuar viendo".)

**`SettingCornerPicker`** (`lib/ui/settings/widgets/setting_corner_picker.dart`) — selector 2x2.
`SettingCornerPicker({required String title, required String value, required ValueChanged<String> onChanged})` con `value` ∈ `{'tl','tr','bl','br'}`. Un rectángulo (~110×64) con un punto tocable en cada esquina; la esquina activa se rellena con el acento, las demás en contorno. Tocar una esquina → `onChanged(code)`.

## 3. Sección `InterfaceSettingsSection`

Subpantalla (Scaffold + AppBar "Interfaz"), enlazada desde una fila nueva en `SettingsScreen` (entre "Reproducción y gestos" y "Acerca de"). Grupos:

**Controles**
- `SettingStepper` — "Auto-ocultar controles": value `controlsAutoHideMs ~/ 1000`, min 1, max 10, step 1, label `'$v s'`, onChanged `(v) => set(controlsAutoHideMs: v * 1000)`.
- `SettingSwitch` `rememberOrientationLock` — "Recordar orientación entre videos".

**Video**
- `SettingSegmented<String>` `defaultAspectMode` — "Aspecto por defecto", opciones `[('fit','Ajustar'),('fill','Llenar'),('stretch','Estirar')]`.

**Overlay de información**
- `SettingSwitch` `showInfoOverlay` — "Mostrar overlay de info".
- **Solo si `showInfoOverlay`**: `SettingChoice<String>` `infoOverlayContent` — "Contenido", opciones `[('name_time','Nombre y tiempo'),('name','Solo nombre'),('remaining','Tiempo restante')]`; y `SettingCornerPicker` `infoOverlayCorner` — "Esquina".

**Biblioteca**
- `SettingSegmented<int>` `libraryColumns` — "Columnas por defecto", opciones `[(1,'1'),(2,'2'),(3,'3')]`.

## 4. Enlace en la lista de secciones

En `settings_screen.dart`, `SettingNavRow(icon: Icons.tune /* o dashboard_customize */, title: 'Interfaz', subtitle: 'Controles, overlay, aspecto, columnas', onTap: → InterfaceSettingsSection)`, insertada **antes de "Acerca de"** (orden final: General, Reproducción y gestos, Interfaz, Acerca de).

## 5. Testing

- **Widget (`setting_choice_test.dart`):** una fila por opción; la seleccionada muestra el check; tocar otra fila llama `onChanged` con su valor.
- **Widget (`setting_corner_picker_test.dart`):** 4 esquinas; tocar una esquina llama `onChanged` con su código ('tl'/'tr'/'bl'/'br'); la activa se distingue.
- **Widget (`interface_section_test.dart`):** cambiar el segmentado de aspecto persiste `defaultAspectMode`; el stepper de auto-ocultar persiste `controlsAutoHideMs` en ms (×1000); con `showInfoOverlay` off, el contenido/esquina NO están; al encenderlo, aparecen; elegir contenido persiste `infoOverlayContent`; columnas persiste `libraryColumns`.
- **`settings_screen_test.dart` (extender):** la raíz lista "Interfaz" y navega.
- `flutter analyze` limpio + suite verde (actual: 303).
- **Device (Pixel 6):** abrir Ajustes → Interfaz; cambiar aspecto por defecto y abrir un video nuevo con ese aspecto; bajar auto-ocultar a 1s y ver los controles ocultarse más rápido; apagar el overlay y ver que desaparece contenido/esquina; mover la esquina y ver el overlay reubicado; cambiar columnas por defecto y ver la densidad de la biblioteca.

## 6. Descomposición del plan

1. `SettingChoice<T>` + `SettingCornerPicker` (2 widgets nuevos) + tests.
2. `InterfaceSettingsSection` (cablea toolkit + los 2 widgets nuevos; contenido/esquina condicionados a `showInfoOverlay`) + fila de navegación en `SettingsScreen` + tests.

## Fuera de alcance

- Implementar el modo `clock` del info-overlay (posible mejora futura; hoy no se expone).
- Aspectos forzados 16:9/4:3/original.
- Sección 4d (Reproducción avanzada).
