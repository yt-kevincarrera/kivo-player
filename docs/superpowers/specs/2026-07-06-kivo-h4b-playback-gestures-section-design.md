# Kivo — Hito 4b: sección "Reproducción y gestos" (diseño)

**Fecha:** 2026-07-06
**Estado:** Diseño aprobado por el usuario; arrancar directo.
**Contexto:** El shell del panel (4a) y el toolkit de filas (`SettingSwitch/Slider/Stepper/Segmented/Color`, `SettingsCard`, `SettingNavRow`) ya están construidos y probados. 4b llena la sección **Reproducción y gestos** cableando controles a campos de `KivoSettings` que ya existen (aplican al instante vía `settingsProvider.set(copyWith(...))`). Decisión previa del usuario: **exponer todo** (incluidos los knobs finos), con un **editor de chips reutilizable** para las dos listas de velocidades.

## 1. Alcance

Una subpantalla `PlaybackGesturesSection` (Scaffold + AppBar "Reproducción y gestos"), enlazada desde una nueva fila en la lista de secciones de `SettingsScreen`. Un widget nuevo reutilizable `SettingSpeedList` para editar listas de velocidades. Todo tema-aware (usa el toolkit existente, que ya deriva del acento).

**Excluido:** `holdRightMin` — no se usa en ningún lado del código (el hold-derecho se rige por `holdRightDetents`); exponer un knob sin efecto confunde, así que **no se muestra**. La háptica ya vive en General (4a), no se repite aquí.

## 2. Controles (agrupados en `SettingsCard`s con etiqueta de grupo)

**Doble toque**
- `SettingStepper` `doubleTapSkipLeft` — "Saltar atrás", min 5, max 60, step 5, label `'$v s'`.
- `SettingStepper` `doubleTapSkipRight` — "Saltar adelante", min 5, max 60, step 5, label `'$v s'`.
- `SettingSwitch` `doubleTapCenterPause` — "Pausar con doble toque al centro".

**Salto y seek**
- `SettingStepper` `centerSkipSeconds` — "Salto de los botones ± ", min 5, max 60, step 5, label `'$v s'`.
- `SettingSwitch` `horizontalSeek` — "Buscar deslizando en horizontal".

**Sensibilidad de gestos**
- `SettingSlider` `brightnessSensitivity` — "Brillo", min 0.5, max 2.0, divisions 15, label `'${v.toStringAsFixed(1)}×'`.
- `SettingSlider` `volumeSensitivity` — "Volumen", igual rango.
- `SettingSlider` `seekSensitivity` — "Seek", igual rango.
- `SettingStepper` `volumeBoostMax` — "Boost máximo de volumen", min 100, max 200, step 10, label `'$v %'`.

**Velocidad**
- `SettingSwitch` `rememberSpeed` — "Recordar velocidad entre videos".
- `SettingSlider` `holdLeftSpeed` — "Velocidad al mantener (izquierda)", min 1.0, max 4.0, divisions 12 (paso 0.25), label `'${v.toStringAsFixed(2)}×'`.
- `SettingSlider` `holdRightMax` — "Velocidad máxima", min 2.0, max 8.0, divisions 12 (paso 0.5), label `'${v.toStringAsFixed(1)}×'`. (Es el tope que usan `setRate`/el panel de velocidad.)
- `SettingSwitch` `holdRightReleaseToNormal` — "Al soltar el acelerador, volver a la velocidad anterior".
- `SettingSegmented<double>` `speedFineStep` — "Paso fino de velocidad", opciones `[(0.01,'0.01×'),(0.05,'0.05×'),(0.1,'0.1×'),(0.25,'0.25×')]`.
- `SettingSpeedList` `speedPresets` — "Velocidades preseleccionadas".
- `SettingSpeedList` `holdRightDetents` — "Escalones del acelerador (hold derecho)".

## 3. Widget nuevo: `SettingSpeedList`

`lib/ui/settings/widgets/setting_speed_list.dart`. API:
`SettingSpeedList({required String title, String? subtitle, required List<double> values, double min = 0.25, double max = 8.0, required ValueChanged<List<double>> onChanged})`.

- Muestra los `values` **ordenados** como chips (borde/acento del tema). Cada chip tiene una ✕ para quitarlo. No se permite dejar la lista vacía: si `values.length == 1`, ese chip no muestra ✕.
- Un chip **"+"** abre un `showModalBottomSheet` con un selector de velocidad (un `Slider`/stepper en `[min, max]`, paso 0.25, con readout) y un botón "Añadir". Al añadir: `{...values, round2(nuevo)}.toList()..sort()` (dedupe por `round2` a 0.01) → `onChanged`.
- Quitar un chip: `onChanged(values donde se quita ese valor)`.
- `round2` viene de `gesture_math.dart` (ya existe).

## 4. Enlace en la lista de secciones

En `settings_screen.dart`, añadir la fila de navegación **antes** de "Acerca de" (orden: General, Reproducción y gestos, Acerca de):
`SettingNavRow(icon: Icons.videogame_asset_outlined, title: 'Reproducción y gestos', subtitle: 'Saltos, sensibilidades, velocidad', onTap: → push PlaybackGesturesSection)`.

## 5. Testing

- **Widget (`setting_speed_list_test.dart`):** muestra un chip por valor ordenado; quitar un chip llama `onChanged` sin ese valor; con un solo valor no hay ✕; el "+" abre el sheet y "Añadir" reporta la lista con el nuevo valor ordenado y deduplicado.
- **Widget (`playback_gestures_section_test.dart`):** cambiar un stepper (p.ej. `doubleTapSkipLeft`) persiste en `settingsProvider`; togglear `horizontalSeek` persiste; el segmentado de `speedFineStep` persiste; `SettingSpeedList` de presets, al quitar un valor, persiste `speedPresets`.
- **Widget (`settings_screen_test.dart`, extender):** la raíz ahora lista "Reproducción y gestos" y tocarla navega a la subpantalla.
- `flutter analyze` limpio + suite completa verde (actual: 295).
- **Device (Pixel 6):** abrir Ajustes → Reproducción y gestos; cambiar cada control y ver que aplica (p.ej. subir sensibilidad de volumen y notar el gesto más sensible; quitar/añadir un preset y verlo en el panel de velocidad; cambiar velocidad máxima y ver el tope del slider del panel).

## 6. Descomposición del plan

1. `SettingSpeedList` (widget reutilizable + sheet de añadir) + tests.
2. `PlaybackGesturesSection` (todos los controles cableados, usa `SettingSpeedList` para las 2 listas) + fila de navegación en `SettingsScreen` + tests.

## Fuera de alcance

- `holdRightMin` (knob muerto; considerar removerlo del modelo en una limpieza aparte).
- Secciones 4c (Interfaz) / 4d (Reproducción avanzada).
- Rediseñar el panel de velocidad (su chip "Guardar" sigue como está; ahora `SettingSpeedList` da además quitar/añadir desde ajustes).
