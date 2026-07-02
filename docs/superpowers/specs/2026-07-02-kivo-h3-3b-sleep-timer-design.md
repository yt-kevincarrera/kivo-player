# Kivo Hito 3 / 3b — Sleep timer (Diseño)

**Fecha:** 2026-07-02
**Estado:** Diseño aprobado (incl. mockups visuales de UI aprobados por el usuario).
**Contexto:** Segundo sub-proyecto de Hito 3. 3a (subtítulos/audio) está completo. Siguen 3c (bucle A-B), 3d (PiP), 3e (segundo plano/audio-only). El botón "Más opciones" de la barra superior (KivoIcons.more, hoy deshabilitado) se activa en este sub-proyecto.

## 1. Alcance

- **Modo tiempo fijo:** duración elegida con el medidor segmentado (8 segmentos × 15 min, tocar el segmento N fija N×15 min, máximo 120) + stepper ±5 min para ajuste fino (rango 5–120 min). La última duración usada se recuerda en settings.
- **Modo "al terminar el episodio":** se detiene cuando el video actual llega a su fin natural. Si el usuario abre otro video con este modo activo, el modo se re-aplica al nuevo video (no queda ligado al original).
- **Aviso previo + fade-out:** ~10s antes de disparar (en ambos modos) aparece un toast y el volumen del reproductor baja gradualmente hasta 0 en esos 10s; al llegar a cero se pausa.
- **El timer es estado global** (no de `PlayerScreen`): sigue corriendo al minimizar al mini-player, al cambiar de video y con la pantalla apagada mientras el proceso viva. Cuenta en tiempo real (wall-clock, `endsAt` absoluto — inmune a throttling de timers), no en tiempo de reproducción: pausar manualmente NO pausa el timer.
- **One-shot:** al disparar (pausa hecha, volumen restaurado) el timer queda desactivado.

**Fuera de alcance:**
- "Detener después de N episodios" — requiere autoplay al siguiente video, que Kivo no tiene. **Autoplay queda anotado como feature obligatoria post-Hito 3** (registrado en memoria del proyecto).
- Supervivencia a la muerte del proceso (sin AlarmManager): si Android mata la app, mueren la reproducción y el timer juntos — aceptable.
- Toast de aviso visible fuera de `PlayerScreen` (p. ej. sobre el mini-player): la pausa global ocurre igual; solo el aviso visual se limita al reproductor abierto.

## 2. Comportamiento

**Disparo (tiempo fijo):** a `endsAt − 10s` → toast + fade del volumen del reproductor (NUNCA el volumen del sistema): `engine.setVolume(playerPercent × factor)` con factor 1.0→0.0 lineal en 10s (ticks de ~250ms). A `endsAt` → `engine.pause()`, restaurar volumen del reproductor al nivel real del usuario (recalculado con `volumeMapping(volumePercentProvider, boost)` — así el próximo play no arranca mudo), desactivar timer.

**Disparo (fin de episodio):** mismo flujo pero el "faltan 10s" se deriva de `duration − position ≤ 10s` del video actual. El video termina solo (no hay autoplay); al detectar el fin → restaurar volumen y desactivar timer. No hace falta `pause()` explícito salvo como cinturón de seguridad.

**Acciones del toast:**
- **Extender** (dorado sólido): reinicia el timer con la duración original elegida (30 min elegidos → 30 min de nuevo). Cancela el fade y restaura el volumen de inmediato. En modo episodio, "Extender" **cancela el timer** (el video va a parar solo al final de todos modos; el usuario queda viendo normal).
- **Desactivar** (fantasma): cancela el timer, cancela el fade, restaura volumen.
- **✕** (cerrar): oculta el toast solamente; el conteo y el fade siguen.

**Interacción con volumen manual:** si el usuario ajusta el volumen por gesto durante el fade, el gesto gana — el fade se cancela silenciosamente (sería una señal clara de que está despierto) pero el timer sigue; el toast permanece.

## 3. UI (mockups aprobados)

**Punto de entrada:** el botón "Más opciones" (tres puntos) se activa y abre un mini bottom sheet de menú (mismo lenguaje: panel `KivoColors.panel`, tarjetas `0xFF182036` radio 13) con una sola entrada por ahora: "Temporizador de apagado" (ícono reloj, subtítulo "Detener la reproducción automáticamente", chevron). El bucle A-B se sumará a este menú en 3c — no se muestra ninguna fila "próximamente".

**Panel del temporizador — sin timer activo** (bottom sheet estilo track_picker: grabber, header "Temporizador de apagado" + botón cerrar):
- Eyebrow "DURACIÓN".
- Stepper: botón − / tiempo grande dorado ("45 min", w800, tabular) / botón +. Paso 5 min, clamp 5–120.
- Medidor segmentado: 8 segmentos (radio 5, alto 22, gap 5), lit = dorado si `duración ≥ (i+1)×15`, apagado `white 14%`. Etiquetas 15/30/45/60/75/90/105/120 debajo (9.5px, faint). Tocar el segmento i fija la duración en (i+1)×15 min.
- Eyebrow "O BIEN" + tarjeta "Al terminar el episodio" (ícono video-play, subtítulo "Se detiene cuando termine este video"). Tocarla la selecciona (estilo activo dorado, como las tarjetas del track picker) y des-selecciona el modo duración; tocar el medidor/stepper vuelve al modo duración.
- Botón primario dorado full-width: "Iniciar · 45 min" o "Iniciar · Al terminar el episodio" según selección. Al tocar: inicia y cierra el sheet.

**Panel del temporizador — timer corriendo:**
- Tiempo restante grande dorado MM:SS (tick cada 1s) + subtítulo "restante · de 30 min" (o "hasta el final del episodio").
- El mismo medidor segmentado de 8 segmentos, ahora drenándose: proporción lit = restante/original (modo fijo) o restante/restante-al-iniciar (modo episodio).
- Dos botones: "Desactivar" (fantasma, borde `white 16%`) y "Extender +30" (dorado sólido, muestra la duración original). En modo episodio solo "Desactivar" (full-width).

**Toast de aviso** (`sleep_warning_toast`, montado en el stack de overlays de `PlayerScreen`, mismo posicionamiento que `ResumePrompt`):
- Cápsula `black 82%`, radio 14, sin borde.
- Fila 1: ícono luna en contenedor dorado tenue (26×26, radio 8) + "Pausando en **0:08**" (cuenta viva, dorado tabular) + ✕.
- Mini-tira segmentada: 10 segmentos de 4px de alto que se apagan uno por segundo, sincronizados con el fade.
- Fila 2: acciones a la derecha — "Desactivar" (texto dim) y "Extender" (píldora dorada sólida, texto `0xFF231705`).

**Indicador de barra superior:** con timer activo, el ícono de tres puntos se tiñe con el color de acento y muestra debajo la cuenta regresiva en miniatura (8.5px, dorado, tabular; en modo episodio muestra el tiempo restante del video). Mismo patrón que el punto dorado de subtítulos de 3a.

## 4. Arquitectura

- **`lib/player/sleep/sleep_timer.dart`** — el núcleo, sin dependencia de UI:
  - `SleepTimerState { SleepTimerMode mode /* fixed | episode */; Duration original; DateTime endsAt /* solo fixed */; bool warning; }` (inmutable).
  - `SleepTimerNotifier extends Notifier<SleepTimerState?>` con `startFixed(Duration)`, `startEpisode()`, `extend()`, `cancel()`. Ticker interno `Timer.periodic(1s)` mientras hay estado. Reloj inyectable (`DateTime Function() now`) para tests.
  - La lógica de fade vive acá (ticks de 250ms en la ventana de warning), llamando `engine.setVolume` y restaurando vía el mapeo existente de `PlayerController`. Escucha `positionProvider`/`durationProvider` para el modo episodio y `volumePercentProvider` para detectar ajuste manual (cancela fade).
- **`lib/ui/player/more/more_menu.dart`** — `showMoreMenu(context, ref)`: el mini-sheet de menú.
- **`lib/ui/player/sleep/sleep_timer_panel.dart`** — `showSleepTimerPanel(context, ref)`: el panel selector/estado activo.
- **`lib/ui/player/sleep/sleep_warning_toast.dart`** — overlay del aviso, derivado de `sleepTimerProvider` (visible cuando `state?.warning == true` y no fue cerrado con ✕ — el "cerrado" es estado local del widget, se resetea con cada nueva ventana de warning).
- **`lib/ui/player/controls/top_bar.dart`** — activar el botón more → `showMoreMenu`; tinte + mini-cuenta cuando `sleepTimerProvider != null`.
- **`lib/ui/player/player_screen.dart`** — montar `SleepWarningToast` en el stack de overlays (junto a `ResumePrompt`).
- **`lib/core/settings/kivo_settings.dart`** — nuevo campo `sleepTimerLastMinutes` (`int`, default `30`), tocando los 6 puntos de inserción estándar.
- **`PlaybackEngine`:** sin cambios — `pause()` y `setVolume()` ya existen.

## 5. Testing

- **Puro (reloj inyectado):** startFixed fija `endsAt` correcto; extend reinicia con la duración original; cancel limpia estado y restaura volumen; el fade produce la secuencia de volúmenes decreciente y restaura al nivel del usuario al disparar; ajuste manual de volumen durante el fade lo cancela sin matar el timer; modo episodio entra en warning con `duration − position ≤ 10s` y termina al llegar al final; cambiar de video re-aplica el modo episodio al nuevo video.
- **Widget:** el menú "Más opciones" abre y navega al panel; seleccionar duración con segmentos/stepper actualiza el botón "Iniciar · X"; iniciar activa el provider y cierra el sheet; el panel activo muestra cuenta y "Desactivar" funciona; el toast aparece con `warning == true`, "Extender" reinicia, "Desactivar" cancela, ✕ lo oculta sin cancelar; el ícono more se tiñe con timer activo.
- **Device (Pixel 6):** timer de 5 min con pantalla apagándose sola → la reproducción se pausa igual; fade-out audible en los últimos 10s; extender desde el toast restaura el volumen de inmediato; modo episodio avisa 10s antes del final del video; el mini-player no mata el timer; la última duración usada aparece pre-seleccionada al reabrir.

## Fuera de alcance (recordatorio)

- Autoplay al siguiente video (→ feature obligatoria futura, post-Hito 3).
- "N episodios" (depende de autoplay).
- Notificación de sistema / AlarmManager.
- 3c (bucle A-B), 3d (PiP), 3e (segundo plano).
