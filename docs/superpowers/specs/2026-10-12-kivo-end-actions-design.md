# Kivo — Acciones al terminar un video

Fecha: 2026-10-12 · Estado: aprobado (diseño validado con el usuario en chat;
el usuario delegó la aprobación del spec y del plan).

## Objetivo

Poder decidir qué pasa cuando un video **termina**: mandarlo a la papelera y/o
hacer algo distinto a seguir con la cola (cerrar el reproductor, cerrar Kivo,
dejar que la pantalla se apague). Pensado para dos usos reales:

- Ver capítulos de una carpeta e ir vaciándola según se ven.
- Dormirse viendo algo: que al acabar se borre y el móvil quede a oscuras.

## Decisiones tomadas con el usuario

1. **Por sesión, desde el reproductor** (menú «Más»). No es un ajuste global:
   se olvida sola al abrir otra cosa desde la biblioteca.
2. **Papelera = cada video de la cola** mientras esté activa.
3. **Fácil de quitar y visible sin estorbar**: chip en los controles con ✕,
   aviso en la tarjeta de cuenta atrás y «Deshacer» después.
4. **Forzar**: «Terminar ya» (créditos) y «Papelera y siguiente» puntual.
5. **El temporizador fijo nunca dispara nada** (pausa a mitad). El modo «fin
   del episodio» sí cuenta como final.
6. **Borrado diferido**: silencioso con acceso a todos los archivos; si no, se
   agrupan y se confirman en **un** diálogo de Android al salir del
   reproductor; lo que quede pendiente se pregunta al volver a Kivo.
7. «Repetir» y «Aleatorio» ya existen (menú «Más» → Reproducción); no se
   duplican aquí.

## Conceptos

### Estado de sesión — `EndActions`

```dart
enum AfterEnd { keepGoing, closePlayer, closeApp, screenOff }
class EndActions { final bool trash; final AfterEnd after; }
```

`endActionsProvider` (Notifier, en memoria). Valor inicial `trash: false,
after: keepGoing`. Se **reinicia** cuando cambia la cola: un
`currentVideoProvider` nuevo cuya `queue` no es idéntica (`identical`) a la
anterior (abrir desde biblioteca, playlist, selector de archivos, bóveda,
atajos). Avanzar por la cola (`advanceTo`, que conserva la lista) no reinicia.
También se reinicia al cerrar la sesión (`CurrentVideoNotifier.clear()`).

`isActive` = `trash || after != keepGoing` → controla el chip.

### Elegibilidad para papelera

Un video es elegible si está en la biblioteca: existe un `VideoItem` en
`mediaIndexProvider` con `uri == session.playbackPath`. Así quedan fuera de
forma natural la bóveda (ruta privada), el selector de archivos (copia en
caché) y lo abierto desde otras apps. Un video no elegible dentro de una cola
con papelera activa simplemente no se borra.

Además la papelera **no aplica con Repetir: video** (no se puede repetir un
archivo borrado): el panel la muestra desactivada con el motivo y el
planificador la ignora.

### Qué es «terminar»

- `completedProvider` → `true` (llega al final reproduciendo, o arrastrando la
  barra hasta el final): **cuenta**.
- El temporizador en modo **fin del episodio** pausa 300 ms antes del final y
  nunca llega `completed`: emite una señal propia (`sleepEpisodeEndProvider`,
  contador) que **cuenta** como final con «el temporizador manda parar».
- Pausa por temporizador fijo, cerrar a mitad, «siguiente» manual, saltar en la
  cola, error de apertura: **no cuentan**.
- Con bucle A-B activo nunca se planifica nada (el bucle no «termina»).

### Planificador puro — `planEnd`

```dart
EndPlan planEnd({
  required EndActions actions,
  required bool eligible,      // el video que acaba está en la biblioteca
  required bool repeatVideo,   // Repetir: video
  required bool loopActive,    // bucle A-B
  required bool autoplayGo,    // shouldAutoplay(...) de hoy (incluye sleep)
});
class EndPlan { final bool trash; final bool advance; final AfterEnd? after; }
```

- `loopActive` → `EndPlan(trash: false, advance: false, after: null)` y el
  flujo actual sigue igual.
- `trash = actions.trash && eligible && !repeatVideo`.
- `after == keepGoing` → `advance = autoplayGo`, `after = null` (exactamente lo
  de hoy).
- Si no → `advance = false`, `after = actions.after`.

Regla resultante con el temporizador: **el temporizador decide si se para;
«Después» decide cómo se para.** N episodios: el planificador corre en cada
final; solo en el último `autoplayGo` es falso.

## Flujo en pantalla completa (`PlayerScreen._onCompleted`)

`endTrashProvider` (`StateProvider<VideoSession?>`): la sesión que irá a la
papelera **cuando se deje**. Se fija al terminar si `plan.trash`; se borra al
abrir sesión nueva (`_start`).

1. `plan.advance` → igual que hoy (tarjeta «Próximo» 3 s si está en pantalla,
   si no avance directo). La tarjeta muestra una línea extra cuando
   `endTrashProvider != null`: icono papelera + «Este video irá a la papelera»
   + botón **Conservar** (pone `endTrashProvider` a null). «Cancelar» de la
   tarjeta = no pasa nada: ni avanza ni borra (también limpia
   `endTrashProvider`). Al avanzar (`_advance`), si `endTrashProvider` sigue
   fijado y es otro video, se **escenifica** el borrado (ver «Cola de
   papelera»).
2. `!plan.advance && plan.after == null` (seguir, pero no hay siguiente /
   autoplay apagado / el temporizador paró): comportamiento de hoy; si
   `plan.trash` se escenifica **ya** (sin cuenta atrás; el aviso «Deshacer»
   hace de red).
3. `plan.after != null`: si está en pantalla, tarjeta de cuenta atrás de 3 s
   con el título de la acción («Cerrando el reproductor», «Cerrando Kivo»,
   «Apagando la pantalla»), la misma línea de papelera con «Conservar», y
   Cancelar / Ahora. Al cumplirse: escenifica el borrado (si queda) y ejecuta
   la acción. Fuera de pantalla (segundo plano, PiP): ambas cosas al instante.
   Si el temporizador estaba activo, se cancela (como hoy).

Implementación de la tarjeta: `AutoplayOverlay` se generaliza. Junto a
`autoplayPendingProvider` (siguiente) se añade `afterPendingProvider`
(`StateProvider<AfterEnd?>`) y `afterConfirmProvider`. La tarjeta pinta la
variante que toque; el anillo y los botones son los mismos.

## Flujo minimizado (`AutoplayCoordinator`)

Mismo planificador. Sin tarjetas: escenifica y ejecuta al instante.
`closePlayer` = lo mismo que la ✕ de la minibarra; `screenOff` = pausar (el
reproductor no retiene la pantalla minimizado).

## Acciones de «Después»

Un único ejecutor `runAfterEnd(AfterEnd, …)`:

- **closePlayer**: pausa, `playerMinimizedProvider = false` y quita la ruta del
  reproductor **sin** minimizar (no queda minibarra). Desde la minibarra: igual
  que su ✕.
- **closeApp**: pausa, cierra el reproductor como arriba, limpia la sesión
  (`CurrentVideoNotifier.clear()`, para que no quede notificación de medios
  pausada) y `SystemNavigator.pop()`.
- **screenOff**: pausa; guarda el brillo actual, baja el brillo de la ventana
  al mínimo y `keepAwake(false)`; el móvil se apaga con su tiempo normal. Se
  restaura (brillo + `keepAwake(true)`) al volver a reproducir o al tocar para
  mostrar los controles. El `dispose` del reproductor ya restablece brillo y
  pantalla.

Hallazgo que motiva `screenOff`: hoy `PlayerScreen` mantiene la pantalla
encendida mientras está montado aunque el video haya acabado.

## «Terminar ya» y «Papelera y siguiente»

- **Terminar ya** (chip y panel; activo cuando `isActive`): corre el mismo
  plan que un final natural pero **sin cuenta atrás** (es una orden
  explícita): escenifica la papelera y avanza / ejecuta la acción. Si es
  «seguir» y no hay siguiente, pausa.
- **Papelera y siguiente** (panel; visible cuando la papelera está apagada y
  el video es elegible): acción puntual, no activa el modo. Escenifica el
  actual y avanza al siguiente si lo hay (si no, pausa).

## Cola de papelera

`PendingTrashStore` (caja Hive `pendingTrash`, proveedor que **lanza** si no
se sobrescribe; override en `main.dart`). Entrada: `uri`, `name`, `id`,
`stagedAtMs`.

`trashQueueProvider` — controlador:

- `stage(VideoItem item, {VideoSession? from})`: guarda la entrada; si el
  video ya no es el actual lo quita del orden de reproducción
  (`CurrentVideoNotifier.dropTrashed(index)`, sin dejar «deshacer» de cola);
  publica `trashUndoProvider` para el aviso; arranca la ventana de deshacer
  (5 s).
- `undo(uri)`: quita la entrada y devuelve el video al orden
  (`restoreTrashed`), si la cola sigue siendo la misma.
- Al expirar la ventana: si el borrado es **silencioso**
  (`movesToTrash && allFilesAccess.isGranted()`) → `VideoActionsController
  .deleteMany([item])` y fuera de la cola. Si no → se queda pendiente.
- `flushInteractive()`: todos los pendientes (salvo el que esté cargado en el
  reproductor) en **un** `deleteMany` (un diálogo de Android). Tras el intento
  se vacía la cola (cancelar en el diálogo = conservar); un error se devuelve
  para mostrarlo con su código KV.
- Bandera `busy` para no reentrar (el diálogo del sistema pausa/reanuda la
  actividad).

Disparadores (en `HomeShell`, que tiene `ScaffoldMessenger`):

- Al salir de la pantalla completa (minimizar o cerrar:
  `playerDismissProvider` pasa de no-null a null) y al cerrar la minibarra →
  `flushInteractive()` directo.
- Al arrancar y al volver a primer plano, fuera del reproductor, con
  pendientes: si es silencioso → se borran sin preguntar; si no → hoja
  «N videos pendientes de ir a la papelera» con la lista y **Mover a la
  papelera / Conservar**.

En Android < 11 no hay papelera: el borrado es definitivo y siempre se agrupa
(textos «eliminar» en vez de «papelera», vía `movesToTrash`).

## Interfaz

- **Menú «Más» → Reproducción**: fila «Al terminar» con resumen
  («Nada», «Papelera», «Papelera · Cerrar Kivo»…). Abre el panel.
- **Panel «Al terminar»** (hoja, mismo estilo que el temporizador, con atrás
  al menú):
  - «Mover a la papelera» con píldora No/Sí; subtítulo «Cada video de la cola,
    al acabar» o el motivo de desactivado («Este video no está en tu
    biblioteca», «No disponible con Repetir: video»).
  - «Después»: cuatro filas seleccionables con icono (Seguir normal · Cerrar
    el reproductor · Cerrar Kivo · Apagar la pantalla).
  - Botones «Terminar ya» y, si procede, «Papelera y siguiente».
- **Chip** en `ControlsOverlay`, abajo a la izquierda (`left: 14, bottom:
  116`, sube cuando el chip de zoom ocupa ese hueco). Solo con controles
  visibles y `isActive`. Icono de la acción principal + texto corto + ✕
  (desactiva todo). Tocar el cuerpo abre el panel. Mantiene el lenguaje
  cápsula oscura + color de acento.
- **Aviso deshacer** (`TrashUndoToast`, mismo armazón que el de la cola):
  «Movido a la papelera» (silencioso) / «Irá a la papelera al salir» (agrupado)
  / «Se eliminará al salir» (< Android 11) + Deshacer.
- Todo texto nuevo en `app_es.arb` y `app_en.arb`.

## Fuera de alcance

Mover a carpeta, quitar de la playlist, configuración por playlist/carpeta,
ajuste global por defecto, apagar la pantalla a la fuerza (requiere admin del
dispositivo).

## Pruebas

- `planEnd`: tabla de casos (bucle, repetir video, no elegible, cada `AfterEnd`
  con/sin autoplay).
- `endActionsProvider`: se reinicia con cola nueva, no al avanzar.
- `trashQueueProvider` con `FakeMediaFileOps` / `FakeAllFilesAccess` /
  almacén en memoria: escenificar, deshacer, commit silencioso tras la
  ventana, agrupado sin acceso, flush vacía la cola, no borra el video
  cargado, orden de la cola se quita y se restaura.
- Temporizador: el modo episodio emite `sleepEpisodeEndProvider` al llegar al
  final; el fijo no.
- Widgets: chip visible/oculto y ✕; línea de papelera en la tarjeta y
  «Conservar»; tarjeta de acción; panel (desactivado con motivo); aviso
  deshacer; fila del menú.
- Cableado: final natural con papelera → avanza y escenifica el anterior;
  `closePlayer` cierra sin minibarra; temporizador fijo no dispara.
