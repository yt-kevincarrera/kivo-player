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

  Future<ProviderContainer> container({KivoSettings? settings}) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    if (settings != null) await s.update(settings);
    final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
    addTearDown(c.dispose);
    return c;
  }

  test('starts inactive at 1x', () async {
    final c = await container();
    expect(c.read(zoomProvider).scale, 1.0);
    expect(c.read(zoomProvider).active, false);
  });

  test('pinch scales and marks active, respecting zoomMax', () async {
    final c = await container(settings: KivoSettings.defaults().copyWith(zoomMax: 2.0));
    c.read(zoomProvider.notifier).pinch(factor: 8.0, focal: centre, viewport: viewport);
    expect(c.read(zoomProvider).scale, 2.0);
    expect(c.read(zoomProvider).active, true);
  });

  test('panBy is a no-op while inactive and clamps while zoomed', () async {
    final c = await container();
    final n = c.read(zoomProvider.notifier);
    n.panBy(const Offset(50, 50), viewport);
    expect(c.read(zoomProvider).offset, Offset.zero);

    n.pinch(factor: 2.0, focal: centre, viewport: viewport);
    n.panBy(const Offset(9999, 0), viewport);
    expect(c.read(zoomProvider).offset.dx, 200); // (2-1)*400/2
  });

  test('reset returns to 1x and recentres', () async {
    final c = await container();
    final n = c.read(zoomProvider.notifier);
    n.pinch(factor: 3.0, focal: centre, viewport: viewport);
    n.panBy(const Offset(100, 100), viewport);
    n.reset();
    expect(c.read(zoomProvider).scale, 1.0);
    expect(c.read(zoomProvider).offset, Offset.zero);
  });

  test('onVideoChanged resets only in video mode', () async {
    final exit = await container(
        settings: KivoSettings.defaults().copyWith(zoomResetMode: 'exit'));
    exit.read(zoomProvider.notifier).pinch(factor: 2.0, focal: centre, viewport: viewport);
    exit.read(zoomProvider.notifier).onVideoChanged();
    expect(exit.read(zoomProvider).scale, 2.0,
        reason: 'exit mode keeps the zoom across the queue');

    final perVideo = await container(
        settings: KivoSettings.defaults().copyWith(zoomResetMode: 'video'));
    perVideo.read(zoomProvider.notifier).pinch(factor: 2.0, focal: centre, viewport: viewport);
    perVideo.read(zoomProvider.notifier).onVideoChanged();
    expect(perVideo.read(zoomProvider).scale, 1.0);
  });

  test('onPlayerExit resets except in never mode', () async {
    final exit = await container(
        settings: KivoSettings.defaults().copyWith(zoomResetMode: 'exit'));
    exit.read(zoomProvider.notifier).pinch(factor: 2.0, focal: centre, viewport: viewport);
    exit.read(zoomProvider.notifier).onPlayerExit();
    expect(exit.read(zoomProvider).scale, 1.0);

    final never = await container(
        settings: KivoSettings.defaults().copyWith(zoomResetMode: 'never'));
    never.read(zoomProvider.notifier).pinch(factor: 2.0, focal: centre, viewport: viewport);
    never.read(zoomProvider.notifier).onPlayerExit();
    expect(never.read(zoomProvider).scale, 2.0);
  });

  test('never mode persists the settled factor and seeds a fresh container from it',
      () async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(KivoSettings.defaults().copyWith(zoomResetMode: 'never'));
    final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
    addTearDown(c.dispose);

    final n = c.read(zoomProvider.notifier);
    n.pinch(factor: 2.0, focal: centre, viewport: viewport);
    n.persistIfRemembered();
    await Future<void>.delayed(Duration.zero); // set() is async
    expect(c.read(settingsProvider).zoomRemembered, 2.0);

    // A fresh container over the same store seeds from the remembered factor.
    final again = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
    addTearDown(again.dispose);
    expect(again.read(zoomProvider).scale, 2.0);
  });

  test('nothing is persisted outside never mode', () async {
    final c = await container(settings: KivoSettings.defaults().copyWith(zoomResetMode: 'exit'));
    final n = c.read(zoomProvider.notifier);
    n.pinch(factor: 2.0, focal: centre, viewport: viewport);
    n.persistIfRemembered();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(settingsProvider).zoomRemembered, 1.0);
  });

  test('a remembered factor above the current max is clamped on seed', () async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(KivoSettings.defaults()
        .copyWith(zoomResetMode: 'never', zoomRemembered: 8.0, zoomMax: 4.0));
    final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
    addTearDown(c.dispose);
    expect(c.read(zoomProvider).scale, 4.0);
  });
}
