import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/ui/home/home_shell.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _es = l10nFor(const Locale('es'));

Future<ProviderContainer> _pump(WidgetTester t) async {
  for (final ch in [
    'receive_sharing_intent/messages',
    'receive_sharing_intent/events-media',
  ]) {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel(ch),
      (_) async => null,
    );
  }
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
    ],
  );
  addTearDown(c.dispose);
  await pumpLocalized(
    t,
    const HomeShell(),
    theme: KivoTheme.dark(),
    container: c,
  );
  await t.pump();
  return c;
}

Future<void> _tapTitle(WidgetTester t, int times) async {
  for (var i = 0; i < times; i++) {
    await t.tap(find.byKey(const ValueKey('title')));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
    'five quick taps on «Kivo» turn incognito on, five more turn it off',
    (t) async {
      final c = await _pump(t);
      await _tapTitle(t, 5);
      expect(c.read(settingsProvider).incognito, true);
      expect(find.text(_es.libraryIncognitoOnSnackbar), findsOneWidget);
      expect(find.byKey(const Key('incognito-chip')), findsOneWidget);

      await _tapTitle(t, 5);
      expect(c.read(settingsProvider).incognito, false);
      await t.pump(
        const Duration(milliseconds: 500),
      ); // the first one slides out
      expect(find.text(_es.libraryIncognitoOffSnackbar), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('four taps do nothing', (t) async {
    final c = await _pump(t);
    await _tapTitle(t, 4);
    expect(c.read(settingsProvider).incognito, false);
  });
}
