import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/ui/player/state/zoom_state.dart';
import '../../../fakes/fakes.dart';

void main() {
  const viewport = Size(400, 800);
  const centre = Offset(200, 400);

  Future<ProviderContainer> container(String mode) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(KivoSettings.defaults().copyWith(zoomResetMode: mode));
    final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
    addTearDown(c.dispose);
    return c;
  }

  test('exit mode: the zoom survives a video change but not leaving the player',
      () async {
    final c = await container('exit');
    final n = c.read(zoomProvider.notifier);
    n.pinch(factor: 2.0, focal: centre, viewport: viewport);
    n.onVideoChanged();
    expect(c.read(zoomProvider).scale, 2.0);
    n.onPlayerExit();
    expect(c.read(zoomProvider).scale, 1.0);
  });

  test('video mode: every video change recentres', () async {
    final c = await container('video');
    final n = c.read(zoomProvider.notifier);
    n.pinch(factor: 2.0, focal: centre, viewport: viewport);
    n.onVideoChanged();
    expect(c.read(zoomProvider).scale, 1.0);
  });

  test('never mode: neither a video change nor leaving clears it', () async {
    final c = await container('never');
    final n = c.read(zoomProvider.notifier);
    n.pinch(factor: 2.0, focal: centre, viewport: viewport);
    n.onVideoChanged();
    n.onPlayerExit();
    expect(c.read(zoomProvider).scale, 2.0);
    n.reset(); // the chip is the only way out
    expect(c.read(zoomProvider).scale, 1.0);
  });
}
