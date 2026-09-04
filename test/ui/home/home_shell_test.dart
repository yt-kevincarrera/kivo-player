import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/ui/home/home_shell.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

Future<void> _pump(WidgetTester t) async {
  final s = await SettingsService.load(InMemorySettingsStore());
  final container = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
    playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
    bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
  ]);
  addTearDown(container.dispose);
  await pumpLocalized(
    t,
    const HomeShell(),
    theme: KivoTheme.dark(),
    container: container,
  );
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

  testWidgets('back at the Videos root leaves the app instead of popping to a black screen', (t) async {
    final platformCalls = <MethodCall>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _pump(t);
    // The system back gesture on the root route: popping it would empty the
    // root navigator and paint a black void (the reported bug, hit right after
    // exiting a video to the mini-player). Only the platform may end the app.
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();

    expect(platformCalls.map((c) => c.method), contains('SystemNavigator.pop'));
    expect(find.text('Kivo'), findsOneWidget); // still on the library, not a void
  });

  testWidgets('tapping Ajustes shows the settings root; Videos switches back', (t) async {
    await _pump(t);
    await t.tap(find.text('Ajustes'));
    await t.pumpAndSettle();
    // The reset tile sits at the bottom of a ListView that has since grown
    // (Ecualizador joined it), so it is not built until scrolled into view.
    await t.dragUntilVisible(
      find.text('Restablecer valores'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.text('Restablecer valores'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);

    await t.tap(find.text('Videos'));
    await t.pumpAndSettle();
    expect(find.text('Kivo'), findsOneWidget);
    expect(find.text('Restablecer valores'), findsNothing);
  });
}
