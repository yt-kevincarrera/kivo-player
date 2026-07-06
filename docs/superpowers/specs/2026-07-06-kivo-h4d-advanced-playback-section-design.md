# Kivo — Hito 4d: sección "Reproducción avanzada" (diseño)

**Fecha:** 2026-07-06
**Estado:** Diseño aprobado por el usuario; arrancar directo.
**Contexto:** Última sección del panel de Hito 4. Shell + toolkit (incl. `SettingChoice`, `SettingSwitch`, `SettingStepper`) listos. Cablea campos de `KivoSettings`, añade un campo nuevo (`pipAutoOnHome`) con su gate, y hace reseteable el idioma preferido.

## 1. Decisiones (confirmadas)

- **Tira de reproducción:** se queda **siempre visible** (no se re-agrega `queueStripVisible`, no hay toggle).
- **Idiomas preferidos (audio/subs):** en 4d solo se puede **volver a "Automático"** (limpiar). Fijar un idioma concreto se sigue haciendo desde el track picker (coincide con pistas reales; el match es exacto). Requiere hacer los campos nullable **reseteables** (ver §3).
- **Estilo de subtítulos** (tamaño/colores): se queda en la pestaña "Estilo" del track picker (maneja bien el fondo transparente). 4d NO lo duplica.
- **PiP-auto-al-Home:** hoy hardcodeado. Se hace configurable con un campo nuevo `pipAutoOnHome` (default `true`) + gate en el armado de PiP.

## 2. Controles (agrupados)

**Continuar viendo**
- `SettingChoice<String>` `resumeBehavior` — "Al reabrir un video", opciones `[('auto','Automático'),('ask','Preguntar'),('off','Desactivado')]`.
- `SettingStepper` `resumeMinSeconds` — "Mínimo para recordar posición", min 0, max 120, step 5, label `'$v s'`.

**Reproducción**
- `SettingSwitch` `autoplayNext` — "Reproducir el siguiente automáticamente".
- `SettingSwitch` `pipAutoOnHome` (nuevo) — "Miniatura flotante (PiP) al salir al inicio".

**Subtítulos y audio**
- `SettingSwitch` `subtitlesEnabledByDefault` — "Activar subtítulos por defecto".
- `SettingChoice<String?>` `preferredSubtitleLanguage` — "Idioma de subtítulos preferido", opciones dinámicas: `[(null,'Automático'), if (value != null) (value, '$value (elegido)')]`. Elegir "Automático" limpia (null).
- `SettingChoice<String?>` `preferredAudioLanguage` — "Idioma de audio preferido", igual patrón.

## 3. Cambios en el modelo `KivoSettings`

- **Nuevo campo `bool pipAutoOnHome`** (default `true`) en los 6 puntos de inserción (field, ctor, defaults, copyWith param+body, toMap, fromMap).
- **Hacer reseteables a null** `preferredSubtitleLanguage` y `preferredAudioLanguage` en `copyWith` mediante un centinela (hoy `x ?? this.x` impide poner null):
  ```dart
  static const Object _unset = Object();
  KivoSettings copyWith({
    ...,
    Object? preferredSubtitleLanguage = _unset,
    Object? preferredAudioLanguage = _unset,
    ...
  }) => KivoSettings(
    ...,
    preferredSubtitleLanguage: identical(preferredSubtitleLanguage, _unset)
        ? this.preferredSubtitleLanguage : preferredSubtitleLanguage as String?,
    preferredAudioLanguage: identical(preferredAudioLanguage, _unset)
        ? this.preferredAudioLanguage : preferredAudioLanguage as String?,
    ...);
  ```
  Seguro: los únicos llamadores (track picker) pasan un `String` (no `_unset`, no null-para-mantener), así que fijar sigue funcionando y ahora `copyWith(preferredSubtitleLanguage: null)` limpia.

## 4. Gate de PiP-auto-al-Home

En `player_screen.dart` `_armPip()`: si `!settings.pipAutoOnHome`, `_pip.disarm()` y `return` (así `onUserLeaveHint` nativo no entra a PiP); si no, `_pip.arm(...)` como hoy. (`disarm()` ya existe — lo usa `dispose`.)

## 5. Enlace en la lista de secciones

`SettingNavRow(icon: Icons.play_circle_outline, title: 'Reproducción avanzada', subtitle: 'Continuar, autoplay, subtítulos, PiP', onTap: → AdvancedPlaybackSection)`, insertada **antes de "Acerca de"** (orden final: General, Reproducción y gestos, Interfaz, Reproducción avanzada, Acerca de).

## 6. Testing

- **Unit (`settings_service_test.dart`, extender):** `pipAutoOnHome` round-trip (6 puntos); `copyWith(preferredSubtitleLanguage: null)` limpia a null; `copyWith(preferredSubtitleLanguage: 'en')` fija 'en'; `copyWith()` sin ese arg mantiene el valor previo.
- **Widget (`advanced_playback_section_test.dart`):** cambiar resume a 'off' persiste `resumeBehavior`; togglear autoplay persiste; togglear `pipAutoOnHome` persiste; con un idioma preseleccionado ('en'), elegir "Automático" limpia `preferredSubtitleLanguage` a null.
- **Widget (`settings_screen_test.dart`, extender):** la raíz lista "Reproducción avanzada" y navega.
- **Gate de PiP:** verificación en device (difícil de unit-test con el PlayerScreen completo).
- `flutter analyze` limpio + suite verde (actual: 311).
- **Device (Pixel 6):** Ajustes → Reproducción avanzada; poner resume en "Preguntar" y reabrir un video (sale el prompt); apagar autoplay y ver que no avanza al terminar; **apagar PiP-auto** y salir al Home → NO entra a PiP (con on, sí); resetear idioma preferido a Automático.

## 7. Descomposición del plan

1. Modelo: `KivoSettings` gana `pipAutoOnHome` (6 puntos) + `copyWith` reseteable para los 2 idiomas; gate de `pipAutoOnHome` en `player_screen._armPip`. Tests de modelo.
2. `AdvancedPlaybackSection` (todos los controles, idiomas con reset a Automático, switch de PiP-auto) + fila de navegación en `SettingsScreen` + tests.

## Fuera de alcance

- Fijar un idioma concreto desde ajustes (se hace en el track picker).
- Estilo de subtítulos en 4d (queda en el track picker).
- Toggle de la tira (se queda siempre-on).
- Autoplay estando minimizado (4e, aparte).
