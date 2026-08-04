import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/ui/player/tutorial/gesture_map_content.dart';

void main() {
  KivoSettings base() => KivoSettings.defaults();

  List<String> labelsOf(GestureMapPage p) => p.hints.map((h) => h.label).toList();

  test('three pages, in teaching order', () {
    final pages = gestureMapPages(base(), pipSupported: true);
    expect(pages.length, 3);
    expect(pages[0].title, 'Toques');
    expect(pages[1].title, 'Arrastres');
    expect(pages[2].title, 'Botones');
  });

  test('tap labels use the configured skip amounts', () {
    final pages = gestureMapPages(
        base().copyWith(doubleTapSkipLeft: 15, doubleTapSkipRight: 30),
        pipSupported: true);
    expect(labelsOf(pages[0]), contains('Doble toque · −15 s'));
    expect(labelsOf(pages[0]), contains('Doble toque · +30 s'));
  });

  test('the center-pause hint disappears when the setting is off', () {
    final on = gestureMapPages(base().copyWith(doubleTapCenterPause: true),
        pipSupported: true);
    final off = gestureMapPages(base().copyWith(doubleTapCenterPause: false),
        pipSupported: true);
    expect(on[0].hints.any((h) => h.zone == MapZone.centerThird), true);
    expect(off[0].hints.any((h) => h.zone == MapZone.centerThird), false);
  });

  test('the seek hint disappears when horizontal seek is off', () {
    final off = gestureMapPages(base().copyWith(horizontalSeek: false),
        pipSupported: true);
    expect(labelsOf(off[1]).any((l) => l.contains('Buscar')), false);
  });

  test('drag labels use the configured boost cap and hold speed', () {
    final pages = gestureMapPages(
        base().copyWith(volumeBoostMax: 150, holdLeftSpeed: 2.5),
        pipSupported: true);
    expect(labelsOf(pages[1]), contains('Arrastra · Volumen (hasta 150%)'));
    expect(labelsOf(pages[1]).any((l) => l.contains('2.5×')), true);
  });

  test('PiP is only listed when the device supports it', () {
    final yes = gestureMapPages(base(), pipSupported: true);
    final no = gestureMapPages(base(), pipSupported: false);
    expect(yes[2].hints.any((h) => h.icon == MapIcon.pip), true);
    expect(no[2].hints.any((h) => h.icon == MapIcon.pip), false);
  });

  test('every button hint carries an icon and a bar zone', () {
    final buttons = gestureMapPages(base(), pipSupported: true)[2].hints;
    for (final h in buttons.where((h) => h.zone != MapZone.footer)) {
      expect(h.icon, isNotNull, reason: h.label);
      expect(h.zone, anyOf(MapZone.topBar, MapZone.bottomBar));
    }
  });
}
