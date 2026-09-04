import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/ui/player/tutorial/gesture_map_content.dart';
import '../../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

void main() {
  KivoSettings base() => KivoSettings.defaults();

  List<String> labelsOf(GestureMapPage p) => p.hints.map((h) => h.label).toList();

  test('three pages, in teaching order', () {
    final pages = gestureMapPages(_l10n, base(), pipSupported: true);
    expect(pages.length, 3);
    expect(pages[0].title, _l10n.playerTutorialPageTaps);
    expect(pages[1].title, _l10n.playerTutorialPageDrags);
    expect(pages[2].title, _l10n.playerTutorialPageButtons);
  });

  test('tap labels use the configured skip amounts', () {
    final pages = gestureMapPages(
        _l10n,
        base().copyWith(doubleTapSkipLeft: 15, doubleTapSkipRight: 30),
        pipSupported: true);
    expect(labelsOf(pages[0]), contains(_l10n.playerTutorialDoubleTapBack(15)));
    expect(labelsOf(pages[0]), contains(_l10n.playerTutorialDoubleTapForward(30)));
  });

  test('the center-pause hint disappears when the setting is off', () {
    final on = gestureMapPages(_l10n, base().copyWith(doubleTapCenterPause: true),
        pipSupported: true);
    final off = gestureMapPages(_l10n, base().copyWith(doubleTapCenterPause: false),
        pipSupported: true);
    expect(on[0].hints.any((h) => h.zone == MapZone.centerThird), true);
    expect(off[0].hints.any((h) => h.zone == MapZone.centerThird), false);
  });

  test('the pinch-zoom hints are taught, and use the configured max', () {
    final pages = gestureMapPages(_l10n, base().copyWith(zoomMax: 6.0), pipSupported: true);
    expect(labelsOf(pages[1]), contains(_l10n.playerTutorialPinchZoom('6×')));
    expect(labelsOf(pages[1]), contains(_l10n.playerTutorialZoomPan));
  });

  test('the pinch-zoom hints disappear when pinch zoom is off', () {
    final off = gestureMapPages(_l10n, base().copyWith(pinchZoom: false), pipSupported: true);
    expect(labelsOf(off[1]).any((l) => l.contains('Pellizca')), false);
    expect(labelsOf(off[1]).any((l) => l.contains('Encuadrar')), false);
  });

  test('the seek hint disappears when horizontal seek is off', () {
    final off = gestureMapPages(_l10n, base().copyWith(horizontalSeek: false),
        pipSupported: true);
    expect(labelsOf(off[1]).any((l) => l.contains('Buscar')), false);
  });

  test('drag labels use the configured boost cap and hold speed', () {
    final pages = gestureMapPages(
        _l10n,
        base().copyWith(volumeBoostMax: 150, holdLeftSpeed: 2.5),
        pipSupported: true);
    expect(labelsOf(pages[1]), contains(_l10n.playerTutorialDragVolume(150)));
    expect(labelsOf(pages[1]).any((l) => l.contains('2.5×')), true);
  });

  test('PiP is only listed when the device supports it', () {
    final yes = gestureMapPages(_l10n, base(), pipSupported: true);
    final no = gestureMapPages(_l10n, base(), pipSupported: false);
    expect(yes[2].hints.any((h) => h.icon == MapIcon.pip), true);
    expect(no[2].hints.any((h) => h.icon == MapIcon.pip), false);
  });

  test('every button hint carries an icon and a bar zone', () {
    final buttons = gestureMapPages(_l10n, base(), pipSupported: true)[2].hints;
    for (final h in buttons.where((h) => h.zone != MapZone.footer)) {
      expect(h.icon, isNotNull, reason: h.label);
      expect(h.zone, anyOf(MapZone.topBar, MapZone.bottomBar));
    }
  });
}
