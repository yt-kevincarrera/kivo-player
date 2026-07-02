# Kivo Hito 3 / 3c — Bucle A-B (Diseño)

**Fecha:** 2026-07-02
**Estado:** Diseño aprobado (mockups: chip píldora + popover de ajuste sobre el video).
**Contexto:** Tercer sub-proyecto de Hito 3. 3a (pistas) y 3b (sleep timer) completos y verificados en dispositivo. Siguen 3d (PiP) y 3e (segundo plano). El menú "Más opciones" (creado en 3b) gana su segunda entrada.

## 1. Comportamiento

- **Activación:** menú "Más opciones" → nueva fila "Bucle A-B" (subtítulo "Repetir un fragmento del video"). Al tocarla se cierra el menú y aparece el **chip flotante** sobre los controles.
- **Chip cíclico (píldora horizontal):** tres estados, un toque avanza:
  1. `armedA` — "Marcar A": toque fija A en la posición actual.
  2. `armedB` — "Marcar B" + recordatorio `A 14:32`: toque fija B y **arranca el bucle**.
  3. `active` — chip dorado con el rango `14:32–15:58`: toque **desactiva** todo (el chip desaparece; se vuelve a empezar desde el menú).
- **Reglas de marcado:** si B se marca en una posición anterior a A, se intercambian. Rango mínimo **1 segundo**: una marca de B a <1s de A se ignora (el chip sigue en `armedB`).
- **Bucle corriendo:** cuando la posición alcanza B → salto instantáneo a A (`engine.seek(A)` directo, sin pasar por el controller). Convive sin caso especial con velocidad de reproducción y sleep timer.
- **Seek manual fuera del rango lo desactiva:** todo seek de usuario pasa por `PlayerController.seekTo` (seek bar, double-tap skip, gestos); ahí se notifica al bucle — si está `active` y el destino cae fuera de `[A−1s, B+1s]`, se cancela silenciosamente. Los saltos propios del bucle usan `engine.seek` directo y no disparan esta vía. En fases `armedA`/`armedB` el seek no cancela (estás buscando el punto).
- **Ajuste fino (popover sobre el video):** long-press en el chip `active` abre un popover flotante junto al chip (el video sigue visible): filas A y B con −1s / timestamp / +1s. **Cada toque en ±1 aplica el ajuste y salta a ese punto** para verificarlo al oído/ojo. Clamps: `0 ≤ A ≤ B−1s` y `A+1s ≤ B ≤ duración`. Se cierra tocando fuera.
- **No persiste:** cambiar de video (cambio en `currentVideoProvider`) cancela el bucle. No se guarda nada en settings ni por video.
- **Menú con bucle existente:** la fila del menú refleja el estado (subtítulo "Activo · 14:32–15:58" o "Marcando…") y tocarla **desactiva** el bucle.
- **Visibilidad del chip:** vive dentro del overlay de controles — aparece y se auto-oculta con ellos. Con controles ocultos el bucle sigue funcionando; tocar la pantalla los trae de vuelta con el chip.

## 2. Visualización en la seek bar

Con bucle `active` (y también con A ya fijado en `armedB`):
- **Banda resaltada** entre A y B: dorado ~28% de opacidad, apenas más alta que el track.
- **Marcadores verticales** de ~2.5px en A y B con la letrita "A"/"B" encima (7.5px, dorado).
- Implementado como capa `IgnorePointer` + `CustomPaint` apilada sobre el `Slider` existente en `seek_bar.dart` (fracciones = ms/totalMs) — cero cambios al gesture handling del slider.

## 3. Arquitectura

- **`lib/player/loop/ab_loop.dart`** — núcleo sin UI:
  - `enum AbLoopPhase { armedA, armedB, active }`
  - `class AbLoopState { final AbLoopPhase phase; final Duration? a; final Duration? b; }` (inmutable; `a` non-null desde `armedB`; `a` y `b` non-null en `active`).
  - `abLoopProvider = NotifierProvider<AbLoopNotifier, AbLoopState?>` (null = sin bucle).
  - `AbLoopNotifier`: `begin()` (→`armedA`), `mark()` (cicla usando la posición actual; en `active` = `cancel()`), `nudgeA(int)/nudgeB(int)` (segundos ±, clamp, y `engine.seek` al punto ajustado), `cancel()`, `userSeeked(Duration target)` (cancela si `active` y target fuera de rango±1s). Listeners en `build()`: `positionProvider` (salto en B), `currentVideoProvider` (cancel al cambiar).
- **`lib/player/control/player_controller.dart`** — `seekTo` notifica `abLoopProvider.notifier.userSeeked(p)` antes de buscar.
- **`lib/ui/player/loop/ab_loop_chip.dart`** — chip píldora + popover de ajuste (estado local del widget para popover abierto/cerrado; long-press abre, tap fuera cierra). Montado en el stack de `ControlsOverlay`, esquina inferior derecha sobre la barra.
- **`lib/ui/player/controls/seek_bar.dart`** — capa de rango (banda + marcadores) derivada de `abLoopProvider`.
- **`lib/ui/player/more/more_menu.dart`** — segunda `_MenuRow` "Bucle A-B" con subtítulo dinámico según estado; toca→`begin()` o `cancel()`.
- Sin cambios en `PlaybackEngine` (usa `seek` existente) ni en settings.

## 4. Testing

- **Puro (provider):** ciclo begin→mark→mark arma el bucle con A/B correctos; B antes de A intercambia; marca a <1s se ignora; posición ≥ B dispara seek(A); `userSeeked` fuera de rango cancela y dentro no; en fases armed no cancela; nudges ajustan con clamp y buscan al punto; cambio de video cancela.
- **Widget:** el chip muestra "Marcar A"→"Marcar B"→rango al ciclar; long-press abre el popover y ±1 ajusta; la fila del menú activa el modo y con bucle activo lo desactiva; la seek bar pinta la banda cuando hay bucle (por key del CustomPaint).
- **Device (Pixel 6):** marcar A y B en una escena y verificar el salto limpio en B; ajustar ±1s y oír el cambio; seek fuera del rango lo apaga; double-tap skip fuera del rango lo apaga; cambiar de video lo apaga; el chip se oculta/aparece con los controles; funciona igual a 2x.

## Fuera de alcance

- Persistencia del bucle (por video o global).
- Múltiples bucles / lista de segmentos.
- Arrastre de marcadores directo en la seek bar.
- 3d (PiP), 3e (segundo plano/audio-only).
