# Kivo — Hito 1: Núcleo del reproductor (Diseño)

**Fecha:** 2026-06-28
**Estado:** Diseño aprobado — pendiente de revisión final del usuario
**Plataforma objetivo:** Android primero (arquitectura preparada para iOS después)

---

## 1. Visión

Kivo es un reproductor de video local para móvil, sin anuncios, sin descargas, sin nada
online y (por ahora) sin reproducción de música. La obsesión del proyecto es la **UX** y
el **performance**, con un principio transversal:

> **Casi todo lo que tenga un valor debe ser configurable.**

Paleta: **azul, negro y dorado**. Estética moderna, minimalista pero completa.

El proyecto se construye por **hitos**, cada uno con su propio spec → plan → implementación:

- **Hito 1 (este documento):** núcleo del reproductor.
- **Hito 2:** biblioteca (escaneo, carpetas/lista, búsqueda, sort, filtros, "continuar viendo").
- **Hito 3:** avanzado (subtítulos, pistas de audio, modo solo-audio + segundo plano, PiP, temporizador, A-B loop).
- **Hito 4:** panel de personalización completo.

---

## 2. Alcance del Hito 1

### Dentro

- Integración de **media_kit** (libmpv) como motor de reproducción para soportar el 90%+ de formatos con buen performance.
- Apertura de un video por **"abrir con"** (share intent) y por **selector de archivo** in-app.
- **Cola por carpeta:** al abrir un video se escanean los videos hermanos de su carpeta para armar la cola (sin biblioteca).
- **Sistema de settings base** (persistente) sobre el que nace cada feature ya configurable.
- **Controles**: barra superior, controles centrales, barra inferior, cola de miniaturas, overlay de info permanente.
- **Sistema de gestos completo**: tap, doble-tap, arrastre vertical (brillo/volumen), arrastre horizontal (seek), mantener-izquierda y mantener-derecha (velocidad).
- **Selector de velocidad granular** dedicado.
- **Reanudación (resume)** por archivo.
- **Lock** del reproductor, **rotación**, **modos de aspecto**.
- **Tema** azul/negro/dorado.

### Fuera (hitos posteriores)

- Biblioteca, búsqueda, filtros, sort, vista de carpetas global (Hito 2).
- Subtítulos, pistas de audio, modo solo-audio real, segundo plano/pantalla apagada, PiP funcional, temporizador, A-B loop (Hito 3).
- Panel de personalización completo (Hito 4).

> Los botones de **subtítulos, PiP y solo-audio** aparecen en la UI del Hito 1 pero **desactivados** ("próximamente"); su función llega en Hito 3.

---

## 3. Stack y arquitectura

| Pieza | Elección | Razón |
|---|---|---|
| Framework | **Flutter** | Multiplataforma, un solo código. |
| Motor de video | **media_kit** (libmpv) | Reproduce casi todo, hardware accel, buen performance. |
| Estado | **Riverpod** | Reactivo y granular: rebuilds quirúrgicos (clave para performance) y composición de providers (ideal para settings). |
| Persistencia | **Hive** | Ligero (APK pequeño), rápido, sin SQL. Guarda settings + posiciones de resume. |

### Principios de arquitectura

Arquitectura **en capas pragmática** (Clean donde paga, sin su burocracia donde no):

- La **inversión de dependencias** se aplica en la **frontera de plataforma** (`platform/`): interfaces para orientación, brillo, volumen, wakelock, share intent. Android implementa ahora; iOS rellena después sin reescribir el núcleo.
- El núcleo de reproducción es **testeable** y desacoplado de la UI.
- No se crean `UseCase`/`Repository` para operaciones triviales (YAGNI). En Hito 2, cuando la biblioteca tenga varias fuentes de datos, se introducirá un `repository` formal donde sí aporta.

### Estructura de carpetas

```
lib/
  core/
    settings/        # modelo de settings, providers, persistencia Hive
    theme/           # tema azul/negro/dorado
    utils/
  player/
    engine/          # wrapper sobre media_kit, estado de reproducción
    queue/           # escaneo de carpeta y cola de videos
    resume/          # guardado/lectura de posiciones por archivo
  ui/
    player/          # pantalla del reproductor
      controls/      # barra superior, inferior, info overlay
      gestures/      # detector y mapa de gestos
      speed/         # panel de velocidad y selector vertical
      queue/         # tira de miniaturas
      hud/           # overlays de brillo/volumen/seek/velocidad
  platform/
    interfaces/      # contratos (orientación, brillo, volumen, wakelock, intent)
    android/         # implementaciones Android
```

---

## 4. Sistema de settings (base)

Servicio de settings tipado, persistido en Hive y expuesto vía Riverpod. Cada widget
relevante **observa** los valores que le importan y reacciona. Cada feature del Hito 1
nace leyendo de aquí (aunque al inicio haya pocos valores), para no retrofittear después.

**Valores configurables introducidos en Hito 1:**

| Categoría | Valor | Default |
|---|---|---|
| Gestos | Segundos de salto doble-tap (izq) | 10 s |
| Gestos | Segundos de salto doble-tap (der) | 10 s |
| Gestos | Doble-tap centro = play/pausa | on |
| Gestos | Sensibilidad de brillo | media |
| Gestos | Sensibilidad de volumen | media |
| Gestos | Sensibilidad de seek horizontal | media |
| Gestos | Seek por arrastre horizontal | on |
| Gestos | Háptica en gestos | on |
| Volumen | Boost máximo (>100%) | 150% |
| Velocidad | Valor de mantener-izquierda | 2.0x |
| Velocidad | Rango del selector mantener-derecha | 1.0x–4.0x |
| Velocidad | Al soltar mantener-derecha vuelve a normal | on |
| Velocidad | Paso fino del selector dedicado | 0.01 |
| Velocidad | Presets visibles (chips) | 0.5 / 0.75 / 1.0 / 1.25 / 1.5 / 1.75 / 2.0 |
| Velocidad | Recordar velocidad entre videos | off |
| Centro | Segundos de ⏪/⏩ (independientes del doble-tap) | 10 s |
| Controles | Delay de auto-ocultar | 3 s |
| Info overlay | Mostrar overlay permanente | on |
| Info overlay | Contenido (nombre, actual/total, restante, reloj) | nombre + actual/total |
| Info overlay | Esquina | superior izquierda |
| Aspecto | Modo por defecto | ajustar (fit) |
| Reanudación | Comportamiento (auto / preguntar / off) | auto |
| Reanudación | Umbral mínimo para guardar | 5 s |
| Rotación | Recordar bloqueo de orientación | on |

---

## 5. Motor de reproducción (`player/engine`)

- Wrapper sobre media_kit que expone estado como providers Riverpod: `position`, `duration`,
  `isPlaying`, `speed`, `buffering`, `aspectMode`, `isLocked`, etc.
- **`position`** vive en su propio provider de alta frecuencia para que **solo** la barra de
  seek y el overlay de tiempo se redibujen (resto del árbol intacto).
- Decodificación hardware por defecto; el toggle hardware/software es de Hito 3 pero la
  capa queda preparada.

---

## 6. Sistema de gestos (`ui/player/gestures`)

Mapa por zonas (pantalla en horizontal). **Franjas muertas** arriba/abajo para no chocar con
gestos del sistema (notch, barra de navegación).

| Gesto | Zona | Acción |
|---|---|---|
| 1 tap | cualquiera | Mostrar/ocultar controles (fade, auto-hide configurable). |
| Doble-tap | izquierda | Retroceder N s (configurable, animación de onda). |
| Doble-tap | derecha | Adelantar N s (configurable, animación de onda). |
| Doble-tap | centro | Play/pausa (configurable on/off). |
| Arrastre vertical | izquierda | Brillo (HUD propio). |
| Arrastre vertical | derecha | Volumen, con boost >100% (HUD propio). |
| Arrastre horizontal | cualquiera | Seek/scrub con miniatura de frame + delta. |
| Mantener | izquierda | Acelera a valor fijo (def. 2x) mientras se mantiene; soltar vuelve a normal. |
| Mantener | derecha | Selector de velocidad vertical (ver §7); soltar vuelve a normal (configurable). |

Háptica sutil al cruzar umbrales (configurable). Todos los HUD con estilo del tema.

---

## 7. Control de velocidad

### Mantener-derecha — selector vertical (momentáneo)
Al mantener, aparece una **escalera de zonas** anclada al dedo: abajo = lento, arriba = rápido
(1.0x–4.0x configurable). Pasos discretos con **tick háptico** al cruzar y lector grande con la
velocidad. **Al soltar vuelve a normal** (configurable).

### Selector dedicado (botón "velocidad")
Panel con:
- **Lector grande** con 2 decimales (ej. `1.12x`).
- **+/−** de paso fino (`0.01`, configurable); mantener pulsado acelera el ajuste.
- **Slider** libre que **imanta** suavemente a breakpoints comunes (0.5 / 0.75 / 1.0 / 1.25 / 1.5 / 2.0 / 3.0 / 4.0); se ignoran arrastrando un poco más.
- **Chips** de presets (configurables) + opción de **guardar preset propio**.
- Botón **↺ Normal (1.0x)**.
- Rango máximo: **4.0x** (configurable).

---

## 8. UI de controles (`ui/player/controls`)

Aparecen/desaparecen con 1 tap y fade; scrims (degradados) para legibilidad sobre cualquier video.

### Overlay de info permanente
Arriba a la izquierda, **discreto y siempre visible** aunque los controles estén ocultos:
`nombre del archivo` + `actual / total` (ej. `1:00:53 / 1:08:24`). Toggle **👁** (en la barra
superior) lo activa/desactiva; **la elección se persiste**. Configurable: contenido y esquina.

### Barra superior
- Izquierda: ← volver + título e info del archivo (resolución, duración).
- Derecha: **💬 subtítulos** · **👁 info-toggle** · **🎧 solo-audio** · **⋮ más**.
  (Subtítulos y solo-audio **desactivados** en Hito 1.)

### Centro
- **⏪ N s** · **play/pausa** · **⏩ N s** (N independiente del doble-tap, configurable).

### Cola de miniaturas
- **Siempre visible** cuando los controles están visibles, sobre la barra inferior.
- Videos de la **misma carpeta**; el actual resaltado en dorado con "▶ AHORA".
- Barra azul de progreso = ya visto. Scroll horizontal con fade en el borde. Tocar = saltar.

### Barra inferior
- Tiempos (el derecho alterna total ↔ restante al tocarlo) + **seek** con knob dorado y
  **miniatura de frame on-demand** (ver §9).
- Toolbar: **velocidad** (abre panel) · **🗗 PiP** (desactivado) · **🔒 bloquear** · **⤢ aspecto** · **⟳ rotar**.

### Lock
Al bloquear se ocultan **todos** los controles y gestos; queda solo un candado pequeño que se
**mantiene pulsado** para desbloquear (evita toques accidentales).

---

## 9. Barra de seek con miniatura de frame (Enfoque A)

Al arrastrar el seek se muestra una **miniatura del frame** de esa posición, generada
**on-demand** (instancia ligera de mpv aparte), con throttling y caché de las últimas
posiciones. **No** penaliza la apertura del video ni usa almacenamiento extra. Si en pruebas
reales se nota lag, se evaluará un híbrido.

---

## 10. Cola por carpeta (`player/queue`)

Al abrir un video, se listan los **videos hermanos** de su carpeta (orden natural por nombre)
para poblar la tira de miniaturas. Provee la base de "siguiente/anterior" sin necesidad de la
biblioteca del Hito 2.

---

## 11. Reanudación (`player/resume`)

- Posición guardada **por archivo** (clave estable del path), persistida en Hive.
- Guardado periódico durante reproducción y al pausar/salir; se descarta al llegar cerca del final.
- Al abrir con progreso ≥ umbral: **reanuda automáticamente** y muestra un **toast discreto**
  *"Reanudado desde 1:00:53 · Reiniciar"* con opción de deshacer (sin modal bloqueante).
- Configurable: comportamiento (auto / preguntar / off) y umbral mínimo.

---

## 12. Apertura de video (Hito 1, sin biblioteca)

- **Abrir con** (share intent) desde el explorador u otras apps.
- **Selector de archivo** in-app.
Ambos disparan el escaneo de carpeta para armar la cola.

---

## 13. Tema (`core/theme`)

Tema oscuro base **negro**, acentos **azul** (elementos activos/seleccionados) y **dorado**
(knob de seek, resaltados, énfasis). Estilo moderno y minimalista.

---

## 14. Performance

- Provider de `position` aislado → rebuilds mínimos.
- Miniatura de seek on-demand (sin coste en apertura).
- Hardware decoding por defecto vía media_kit.
- Listas/colas con widgets ligeros y caché de miniaturas.

---

## 15. Testing

- Núcleo (`player/engine`, `resume`, `queue`, `settings`) con tests unitarios sobre interfaces
  mockeadas (las de `platform/` se mockean).
- Lógica de gestos (mapeo zona→acción, umbrales) testeada de forma aislada de los widgets.
- Widget tests para estados de controles (visible/oculto/bloqueado) y para el panel de velocidad.

---

## 16. Notas de secuencia

- La **función real** de subtítulos, PiP y solo-audio es de **Hito 3**; en Hito 1 sus botones
  existen pero están desactivados.
- La tira de miniaturas funciona en Hito 1 vía escaneo de carpeta; en Hito 2 se enriquecerá con
  la biblioteca completa (metadatos, "continuar viendo", peek de otras carpetas).
