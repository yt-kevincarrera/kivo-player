import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/decoder/decoder_controller.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import 'package:kivo_player/ui/player/more/more_menu.dart';
import '../../../fakes/fakes.dart';
import '../../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

const _session = VideoSession(
    playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0);

Future<(ProviderContainer, FakePlaybackEngine, InMemoryTrackPrefsStore)> _pump(
    WidgetTester tester) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  await s.update(s.current.copyWith(decoderAutoFallback: false));
  final prefs = InMemoryTrackPrefsStore();
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
    trackPrefsStoreProvider.overrideWithValue(prefs),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(_session);
  await tester.runAsync(() => c.read(decoderControllerProvider).open(_session));

  await pumpLocalized(
    tester,
    Scaffold(
      body: Center(
        child: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () => showMoreMenu(context, ref),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    container: c,
    theme: KivoTheme.dark(),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (c, engine, prefs);
}

void main() {
  testWidgets('the decoder row shows what mpv is really using', (tester) async {
    await _pump(tester);
    expect(find.text(_l10n.playerMenuDecoder), findsOneWidget);
    expect(find.text(_l10n.playerMenuDecoderActiveHardware), findsOneWidget);
  });

  testWidgets('picking SW switches live and marks it as this video\'s own',
      (tester) async {
    final (_, engine, prefs) = await _pump(tester);
    await tester.tap(find.text(_l10n.playerMenuDecoderSw));
    await tester.pumpAndSettle();

    expect(engine.hwdecWrites.last, 'no');
    expect(prefs.forKey('a.mkv')!.decoder, 'sw');
    expect(
        find.text(_l10n.playerMenuDecoderThisVideoOnly(
            _l10n.playerMenuDecoderActiveSoftware)),
        findsOneWidget);
  });

  testWidgets('picking Auto again leaves nothing saved', (tester) async {
    final (_, _, prefs) = await _pump(tester);
    await tester.tap(find.text(_l10n.playerMenuDecoderSw));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.playerMenuDecoderAuto));
    await tester.pumpAndSettle();
    expect(prefs.forKey('a.mkv'), isNull);
    expect(find.text(_l10n.playerMenuDecoderActiveHardware), findsOneWidget);
  });
}
