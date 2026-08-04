import '../../../core/settings/kivo_settings.dart';

/// Where a hint is anchored. The thirds and the halves are BOTH real: double
/// taps use thirds (`tapZoneOf`) while brightness/volume drags split the screen
/// down the middle — which is exactly why the map separates them by page.
enum MapZone {
  leftThird,
  centerThird,
  rightThird,
  leftHalf,
  rightHalf,
  centerBand,
  lateralEdges,
  fullWidth,
  footer,
  topBar,
  bottomBar,
}

/// The arrow drawn inside a zone, if any.
enum HintArrow { vertical, horizontal, down }

/// Icon slots the map page maps to `KivoIcons`. Kept as an enum so this file
/// stays pure Dart with no Flutter dependency.
enum MapIcon { back, info, subtitles, pip, audio, more, speed, lock, aspect, rotate }

class GestureHint {
  final MapZone zone;
  final String label;
  final HintArrow? arrow;
  final MapIcon? icon;
  const GestureHint(this.zone, this.label, {this.arrow, this.icon});
}

class GestureMapPage {
  final String title;
  final List<GestureHint> hints;
  const GestureMapPage(this.title, this.hints);
}

String _speed(double v) =>
    '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)}×';

/// The whole tutorial, derived from what the user actually has configured: the
/// numbers come from [s], and a gesture the user turned OFF is not taught.
List<GestureMapPage> gestureMapPages(
  KivoSettings s, {
  required bool pipSupported,
}) =>
    [
      GestureMapPage('Toques', [
        GestureHint(MapZone.leftThird, 'Doble toque · −${s.doubleTapSkipLeft} s'),
        if (s.doubleTapCenterPause)
          const GestureHint(MapZone.centerThird, 'Doble toque · Pausa'),
        GestureHint(MapZone.rightThird, 'Doble toque · +${s.doubleTapSkipRight} s'),
        const GestureHint(
            MapZone.footer, 'Un toque · Mostrar u ocultar los controles'),
      ]),
      GestureMapPage('Arrastres', [
        const GestureHint(MapZone.leftHalf, 'Arrastra · Brillo',
            arrow: HintArrow.vertical),
        GestureHint(
            MapZone.rightHalf, 'Arrastra · Volumen (hasta ${s.volumeBoostMax}%)',
            arrow: HintArrow.vertical),
        if (s.horizontalSeek)
          const GestureHint(
              MapZone.fullWidth, 'Arrastra · Buscar con vista previa',
              arrow: HintArrow.horizontal),
        const GestureHint(
            MapZone.lateralEdges, 'Arrastra en el borde · Minimizar',
            arrow: HintArrow.down),
        const GestureHint(MapZone.centerBand,
            'Arrastra en el centro · Girar (con los controles ocultos)',
            arrow: HintArrow.vertical),
        GestureHint(MapZone.footer,
            'Mantén pulsado a la izquierda · ${_speed(s.holdLeftSpeed)}'),
        const GestureHint(MapZone.footer,
            'Mantén y desliza arriba o abajo a la derecha · Escalera de velocidad'),
      ]),
      GestureMapPage('Botones', [
        const GestureHint(MapZone.topBar, 'Minimizar a la mini-barra',
            icon: MapIcon.back),
        const GestureHint(MapZone.topBar, 'Información en pantalla',
            icon: MapIcon.info),
        const GestureHint(MapZone.topBar, 'Subtítulos', icon: MapIcon.subtitles),
        if (pipSupported)
          const GestureHint(MapZone.topBar, 'Imagen en imagen', icon: MapIcon.pip),
        const GestureHint(MapZone.topBar, 'Pistas de audio', icon: MapIcon.audio),
        const GestureHint(
            MapZone.topBar, 'Más opciones · temporizador y bucle A-B',
            icon: MapIcon.more),
        const GestureHint(MapZone.bottomBar, 'Velocidad', icon: MapIcon.speed),
        const GestureHint(MapZone.bottomBar, 'Bloquear la pantalla',
            icon: MapIcon.lock),
        const GestureHint(MapZone.bottomBar, 'Relación de aspecto',
            icon: MapIcon.aspect),
        const GestureHint(MapZone.bottomBar, 'Rotar', icon: MapIcon.rotate),
        const GestureHint(MapZone.footer,
            'Con más de un video en la carpeta aparece la cola sobre los botones'),
      ]),
    ];
