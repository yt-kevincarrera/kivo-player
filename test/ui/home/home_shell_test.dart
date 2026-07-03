import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/ui/home/home_shell.dart';
import '../../fakes/fakes.dart';

Future<void> _pump(WidgetTester t) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  await t.pumpWidget(ProviderScope(
    overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    ],
    child: MaterialApp(theme: KivoTheme.dark(), home: const HomeShell()),
  ));
  await t.pump();
}

void main() {
  testWidgets('shows both bottom tabs and starts on Videos', (t) async {
    await _pump(t);
    expect(find.text('Videos'), findsOneWidget);
    expect(find.text('Ajustes'), findsOneWidget); // only the tab label (settings offstage)
    expect(find.text('Kivo'), findsOneWidget); // library AppBar title
    // The settings tab content is offstage, so its reset tile isn't found yet.
    expect(find.text('Restablecer valores'), findsNothing);
  });

  testWidgets('tapping Ajustes shows the settings root; Videos switches back', (t) async {
    await _pump(t);
    await t.tap(find.text('Ajustes'));
    await t.pumpAndSettle();
    expect(find.text('Restablecer valores'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);

    await t.tap(find.text('Videos'));
    await t.pumpAndSettle();
    expect(find.text('Kivo'), findsOneWidget);
    expect(find.text('Restablecer valores'), findsNothing);
  });
}
