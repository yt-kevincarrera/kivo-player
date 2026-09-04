import '../../../core/settings/kivo_settings.dart';
import '../../../l10n/generated/app_localizations.dart';

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

/// Zoom factors are always whole in the picker (2/4/6/8), so no decimals.
String _zoom(double v) => '${v.toStringAsFixed(0)}×';

/// The whole tutorial, derived from what the user actually has configured: the
/// numbers come from [s], and a gesture the user turned OFF is not taught.
///
/// Takes the resolved [AppLocalizations] rather than a BuildContext: this file
/// otherwise has no Flutter widget dependency, and the only caller
/// (gesture_map_page.dart) already has a context to resolve it from.
List<GestureMapPage> gestureMapPages(
  AppLocalizations l10n,
  KivoSettings s, {
  required bool pipSupported,
}) =>
    [
      GestureMapPage(l10n.playerTutorialPageTaps, [
        GestureHint(MapZone.leftThird, l10n.playerTutorialDoubleTapBack(s.doubleTapSkipLeft)),
        if (s.doubleTapCenterPause)
          GestureHint(MapZone.centerThird, l10n.playerTutorialDoubleTapPause),
        GestureHint(MapZone.rightThird, l10n.playerTutorialDoubleTapForward(s.doubleTapSkipRight)),
        GestureHint(MapZone.footer, l10n.playerTutorialSingleTapToggleControls),
      ]),
      GestureMapPage(l10n.playerTutorialPageDrags, [
        GestureHint(MapZone.leftHalf, l10n.playerTutorialDragBrightness,
            arrow: HintArrow.vertical),
        GestureHint(
            MapZone.rightHalf, l10n.playerTutorialDragVolume(s.volumeBoostMax),
            arrow: HintArrow.vertical),
        if (s.horizontalSeek)
          GestureHint(
              MapZone.fullWidth, l10n.playerTutorialDragSeekPreview,
              arrow: HintArrow.horizontal),
        GestureHint(
            MapZone.lateralEdges, l10n.playerTutorialDragEdgeMinimize,
            arrow: HintArrow.down),
        GestureHint(MapZone.centerBand,
            l10n.playerTutorialDragCenterRotate,
            arrow: HintArrow.vertical),
        if (s.pinchZoom) ...[
          GestureHint(MapZone.fullWidth, l10n.playerTutorialPinchZoom(_zoom(s.zoomMax))),
          GestureHint(MapZone.footer, l10n.playerTutorialZoomPan),
        ],
        GestureHint(MapZone.footer,
            l10n.playerTutorialHoldLeftSpeed(_speed(s.holdLeftSpeed))),
        GestureHint(MapZone.footer, l10n.playerTutorialHoldRightLadder),
      ]),
      GestureMapPage(l10n.playerTutorialPageButtons, [
        GestureHint(MapZone.topBar, l10n.playerTutorialMinimize,
            icon: MapIcon.back),
        GestureHint(MapZone.topBar, l10n.playerTutorialInfoOverlay,
            icon: MapIcon.info),
        GestureHint(MapZone.topBar, l10n.playerSubtitlesTooltip, icon: MapIcon.subtitles),
        if (pipSupported)
          GestureHint(MapZone.topBar, l10n.playerPipTooltip, icon: MapIcon.pip),
        GestureHint(MapZone.topBar, l10n.playerTutorialAudioTracks, icon: MapIcon.audio),
        GestureHint(
            MapZone.topBar, l10n.playerTutorialMoreOptions,
            icon: MapIcon.more),
        GestureHint(MapZone.bottomBar, l10n.playerSpeedTooltip, icon: MapIcon.speed),
        GestureHint(MapZone.bottomBar, l10n.playerTutorialLockScreen,
            icon: MapIcon.lock),
        GestureHint(MapZone.bottomBar, l10n.playerAspectRatioTooltip,
            icon: MapIcon.aspect),
        GestureHint(MapZone.bottomBar, l10n.playerRotateTooltip, icon: MapIcon.rotate),
        GestureHint(MapZone.footer, l10n.playerTutorialQueueHint),
      ]),
    ];
