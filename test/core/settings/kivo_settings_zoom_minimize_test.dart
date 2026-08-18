import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';

void main() {
  test('zoom and minimize fields have the documented defaults', () {
    final d = KivoSettings.defaults();
    expect(d.pinchZoom, true);
    expect(d.zoomMax, 4.0);
    expect(d.zoomResetMode, 'exit');
    expect(d.zoomRemembered, 1.0);
    expect(d.minimizeKeepsPlaying, false,
        reason: "today's pause-on-minimize stays the default");
  });

  test('all five round-trip through toMap/fromMap', () {
    final changed = KivoSettings.defaults().copyWith(
      pinchZoom: false,
      zoomMax: 6.0,
      zoomResetMode: 'never',
      zoomRemembered: 2.5,
      minimizeKeepsPlaying: true,
    );
    final back = KivoSettings.fromMap(changed.toMap());
    expect(back.pinchZoom, false);
    expect(back.zoomMax, 6.0);
    expect(back.zoomResetMode, 'never');
    expect(back.zoomRemembered, 2.5);
    expect(back.minimizeKeepsPlaying, true);
  });

  test('a whole-number zoomMax survives a JSON round-trip as a double', () {
    // JSON writes 4.0 back as an int; a bare `as double` cast would throw.
    final map = KivoSettings.defaults().toMap()..['zoomMax'] = 6;
    expect(KivoSettings.fromMap(map).zoomMax, 6.0);
  });

  test('a settings map written before these fields existed keeps working', () {
    final old = KivoSettings.defaults().toMap()
      ..remove('pinchZoom')
      ..remove('zoomMax')
      ..remove('zoomResetMode')
      ..remove('zoomRemembered')
      ..remove('minimizeKeepsPlaying');
    final back = KivoSettings.fromMap(old);
    expect(back.pinchZoom, true);
    expect(back.zoomMax, 4.0);
    expect(back.zoomResetMode, 'exit');
    expect(back.zoomRemembered, 1.0);
    expect(back.minimizeKeepsPlaying, false);
  });
}
