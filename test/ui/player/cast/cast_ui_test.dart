import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/cast_platform_provider.dart';
import 'package:kivo_player/player/cast/cast_controller.dart';
import 'package:kivo_player/player/cast/dlna_network.dart';
import 'package:kivo_player/player/cast/upnp.dart';
import 'package:kivo_player/ui/player/cast/cast_picker_sheet.dart';
import 'package:kivo_player/ui/player/cast/cast_screen.dart';
import '../../../fakes/fakes.dart';
import '../../../helpers/pump_app.dart';
import '../../../player/cast/cast_controller_test.dart'
    show FakeCastPlatform, FakeTv;

class _FakeDiscovery implements TvDiscovery {
  final ctrl = StreamController<List<DlnaRenderer>>();
  @override
  Stream<List<DlnaRenderer>> search({
    Duration timeout = const Duration(seconds: 5),
  }) => ctrl.stream;
}

final _es = l10nFor(const Locale('es'));
final _tv = DlnaRenderer(
  id: 'uuid:1',
  name: 'Salón',
  model: 'UE55',
  avTransportControl: Uri.parse('http://192.168.1.20/avt'),
);

void main() {
  testWidgets('the picker lists the TVs found and returns the one tapped', (
    t,
  ) async {
    final discovery = _FakeDiscovery();
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
        castPlatformProvider.overrideWithValue(FakeCastPlatform()),
        tvDiscoveryProvider.overrideWithValue(discovery),
      ],
    );
    addTearDown(c.dispose);
    DlnaRenderer? picked;
    await pumpLocalized(
      t,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showCastPicker(context),
            child: const Text('open'),
          ),
        ),
      ),
      container: c,
      theme: KivoTheme.dark(),
    );
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text(_es.castPickerSearching), findsOneWidget);

    discovery.ctrl.add([_tv]);
    await t.pump();
    expect(find.text('Salón'), findsOneWidget);
    expect(find.text('UE55'), findsOneWidget);

    await discovery.ctrl.close();
    await t.pump();
    expect(find.text(_es.castPickerSearching), findsNothing);

    await t.tap(find.text('Salón'));
    await t.pumpAndSettle();
    expect(picked, _tv);
  });

  testWidgets('nothing found: says how to fix it, and can search again', (
    t,
  ) async {
    final discovery = _FakeDiscovery();
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
        castPlatformProvider.overrideWithValue(FakeCastPlatform()),
        tvDiscoveryProvider.overrideWithValue(discovery),
      ],
    );
    addTearDown(c.dispose);
    await pumpLocalized(
      t,
      const Scaffold(body: CastPickerSheet()),
      container: c,
      theme: KivoTheme.dark(),
    );
    await discovery.ctrl.close();
    await t.pump();
    expect(find.text(_es.castPickerEmptyTitle), findsOneWidget);
    expect(find.text(_es.castPickerRetry), findsOneWidget);
  });

  testWidgets(
    'the cast screen is a remote for the TV; stopping hands back where it was',
    (t) async {
      final s = await SettingsService.load(InMemorySettingsStore());
      final tv = FakeTv()..pos = const Duration(minutes: 3);
      final c = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWithValue(s),
          castPlatformProvider.overrideWithValue(FakeCastPlatform()),
          tvTransportFactoryProvider.overrideWithValue((_) => tv),
          localAddressesProvider.overrideWithValue(
            () async => ['192.168.1.33'],
          ),
        ],
      );
      addTearDown(c.dispose);
      await c
          .read(castControllerProvider.notifier)
          .start(_tv, source: '/v/a.mkv', title: 'a.mkv', resumeKey: 'a.mkv');
      Duration? back;
      await pumpLocalized(
        t,
        CastScreen(onStopped: (at) => back = at),
        container: c,
        theme: KivoTheme.dark(),
      );
      await t.pump(const Duration(seconds: 1)); // one poll: 3:00
      expect(find.text(_es.castPlayingOn('Salón')), findsOneWidget);

      await t.tap(find.byKey(const Key('cast-play-pause')));
      await t.pump();
      expect(tv.calls.last, 'pause');

      await t.tap(find.byKey(const Key('cast-stop')));
      await t.pump();
      expect(back, const Duration(minutes: 3));
      expect(c.read(castControllerProvider).active, false);
    },
  );
}
