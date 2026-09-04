import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/ui/home/widgets/folder_options_sheet.dart';
import 'package:kivo_player/ui/settings/sections/hidden_folders_section.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

Future<ProviderContainer> _c() async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  return ProviderContainer(
      overrides: [settingsServiceProvider.overrideWithValue(svc)]);
}

void main() {
  testWidgets('hiding a folder stores it and says the files are untouched',
      (tester) async {
    final c = await _c();
    addTearDown(c.dispose);

    await pumpLocalized(
      tester,
      Consumer(builder: (ctx, ref, _) => Scaffold(
            body: Builder(
              builder: (b) => TextButton(
                onPressed: () => showFolderOptionsSheet(b, ref, 'WhatsApp'),
                child: const Text('open'),
              ),
            ),
          )),
      container: c,
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se borra ni se mueve nada'), findsOneWidget);

    await tester.tap(find.text(_l10n.folderHideTitle));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).excludedFolders, ['WhatsApp']);
    expect(find.text(_l10n.commonUndo), findsOneWidget);

    await tester.tap(find.text(_l10n.commonUndo));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).excludedFolders, isEmpty);
  });

  testWidgets('hiding the same folder twice does not duplicate it', (tester) async {
    final c = await _c();
    addTearDown(c.dispose);
    final s = c.read(settingsProvider);
    await c.read(settingsProvider.notifier)
        .set(s.copyWith(excludedFolders: const ['WhatsApp']));

    await pumpLocalized(
      tester,
      Consumer(builder: (ctx, ref, _) => Scaffold(
            body: Builder(
              builder: (b) => TextButton(
                onPressed: () => showFolderOptionsSheet(b, ref, 'WhatsApp'),
                child: const Text('open'),
              ),
            ),
          )),
      container: c,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.folderHideTitle));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).excludedFolders, ['WhatsApp']);
  });

  testWidgets('the settings screen lists hidden folders and restores them',
      (tester) async {
    final c = await _c();
    addTearDown(c.dispose);
    final s = c.read(settingsProvider);
    await c.read(settingsProvider.notifier)
        .set(s.copyWith(excludedFolders: const ['WhatsApp', 'Telegram']));

    await pumpLocalized(tester, const HiddenFoldersSection(), container: c);
    await tester.pumpAndSettle();

    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Telegram'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('restore-WhatsApp')));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).excludedFolders, ['Telegram']);
  });

  testWidgets('with nothing hidden the settings screen explains itself',
      (tester) async {
    final c = await _c();
    addTearDown(c.dispose);
    await pumpLocalized(tester, const HiddenFoldersSection(), container: c);
    await tester.pumpAndSettle();
    expect(find.text(_l10n.settingsHiddenFoldersEmpty), findsOneWidget);
  });
}
