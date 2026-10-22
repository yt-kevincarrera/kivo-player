import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/player/end_actions/end_actions.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/settings/sections/end_actions_settings_screen.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));
final _trash = find.byKey(const Key('end-default-trash'));
Finder _after(AfterEnd action) =>
    find.byKey(Key('end-default-after-${action.name}'));

Future<ProviderContainer> _container({KivoSettings? initial}) async {
  final service = await SettingsService.load(InMemorySettingsStore());
  if (initial != null) await service.update(initial);
  final container = ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(service),
      mediaFileOpsProvider.overrideWithValue(
        FakeMediaFileOps()..movesToTrash = true,
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  ThemeData? theme,
  double textScale = 1,
}) async {
  await pumpLocalized(
    tester,
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: const EndActionsSettingsScreen(),
      ),
    ),
    container: container,
    theme: theme ?? KivoTheme.dark(),
  );
  await tester.pumpAndSettle();
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('defaults take effect directly without a current video', (
    tester,
  ) async {
    final container = await _container();
    await _pump(tester, container);
    expect(container.read(currentVideoProvider), isNull);
    expect(find.byKey(const Key('end-global-switch')), findsNothing);
    expect(find.byKey(const Key('end-finish-now')), findsNothing);
    expect(find.byKey(const Key('end-trash-and-next')), findsNothing);

    await tester.tap(_trash);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).endActionsGlobal, isTrue);
    expect(container.read(settingsProvider).endActionsTrash, isTrue);
    expect(container.read(endActionsProvider).trash, isTrue);

    await tester.ensureVisible(_after(AfterEnd.closePlayer));
    await tester.tap(_after(AfterEnd.closePlayer));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).endActionsAfter, 'closePlayer');
    expect(container.read(endActionsProvider).after, AfterEnd.closePlayer);

    await tester.ensureVisible(_trash);
    await tester.tap(_trash);
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).endActionsGlobal, isTrue);
    expect(container.read(settingsProvider).endActionsTrash, isFalse);
    await tester.ensureVisible(_after(AfterEnd.keepGoing));
    await tester.tap(_after(AfterEnd.keepGoing));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).endActionsGlobal, isFalse);
    expect(container.read(endActionsProvider).isActive, isFalse);
    expect(container.read(currentVideoProvider), isNull);
  });

  testWidgets(
    'opening shows neutral defaults and leaves a dormant profile off',
    (tester) async {
      final initial = KivoSettings.defaults().copyWith(
        endActionsGlobal: false,
        endActionsTrash: true,
        endActionsAfter: 'closeApp',
      );
      final container = await _container(initial: initial);
      await _pump(tester, container);

      expect(tester.widget<SwitchListTile>(_trash).value, isFalse);
      expect(container.read(settingsProvider).toMap(), initial.toMap());
      expect(container.read(endActionsProvider).isActive, isFalse);
      final group = tester.widget<RadioGroup<AfterEnd>>(
        find.byType(RadioGroup<AfterEnd>),
      );
      expect(group.groupValue, AfterEnd.keepGoing);
    },
  );

  testWidgets('opening settings preserves the temporary player choice', (
    tester,
  ) async {
    final container = await _container();
    const session = VideoSession(
      playbackPath: '/cache/current.mp4',
      displayName: 'current.mp4',
      queue: ['/cache/current.mp4'],
      index: 0,
    );
    container.read(currentVideoProvider.notifier).open(session);
    await container
        .read(endActionsProvider.notifier)
        .setAfter(AfterEnd.screenOff);
    final temporary = container.read(endActionsProvider);
    final before = container.read(settingsProvider).toMap();

    await _pump(tester, container);

    expect(container.read(currentVideoProvider), same(session));
    expect(container.read(endActionsProvider), same(temporary));
    expect(container.read(settingsProvider).toMap(), before);
    expect(tester.widget<SwitchListTile>(_trash).value, isFalse);
    final group = tester.widget<RadioGroup<AfterEnd>>(
      find.byType(RadioGroup<AfterEnd>),
    );
    expect(group.groupValue, AfterEnd.keepGoing);
  });

  testWidgets('restart clears trash and disables it with an explanation', (
    tester,
  ) async {
    final container = await _container();
    await _pump(tester, container);
    await tester.tap(_trash);
    await tester.pumpAndSettle();
    await tester.ensureVisible(_after(AfterEnd.restart));
    await tester.tap(_after(AfterEnd.restart));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).endActionsAfter, 'restart');
    expect(container.read(settingsProvider).endActionsTrash, isFalse);
    expect(tester.widget<SwitchListTile>(_trash).onChanged, isNull);
    expect(find.text(_l10n.endActionsTrashRestart), findsOneWidget);

    await tester.ensureVisible(_after(AfterEnd.keepGoing));
    await tester.tap(_after(AfterEnd.keepGoing));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(_trash).onChanged, isNotNull);
    expect(tester.widget<SwitchListTile>(_trash).value, isFalse);
    expect(container.read(settingsProvider).endActionsGlobal, isFalse);
  });

  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light
        ? KivoTheme.light()
        : KivoTheme.dark();

    testWidgets('${brightness.name}: 320px and 2x text remain scrollable', (
      tester,
    ) async {
      _viewport(tester, const Size(320, 640));
      final container = await _container();
      await _pump(tester, container, theme: theme, textScale: 2);
      expect(tester.takeException(), isNull);

      // Reach every control at the large accessibility size, including the
      // last option below the fold, and exercise the two-line row at the end.
      for (final after in AfterEnd.values) {
        await tester.ensureVisible(_after(after));
        await tester.pumpAndSettle();
        expect(_after(after).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(_after(AfterEnd.screenOff));
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).endActionsAfter, 'screenOff');
      await tester.ensureVisible(_trash);
      await tester.pumpAndSettle();
      expect(_trash.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '${brightness.name}: labeled Material controls meet a11y checks',
      (tester) async {
        _viewport(tester, const Size(440, 1200));
        final semantics = tester.ensureSemantics();
        try {
          final container = await _container();
          await _pump(tester, container, theme: theme);

          expect(
            tester.getSemantics(_trash),
            isSemantics(
              label:
                  '${_l10n.endActionsTrashTitle}\n${_l10n.endActionsDefaultTrashHint}',
              hasToggledState: true,
              isToggled: false,
              isEnabled: true,
              hasTapAction: true,
            ),
          );
          expect(
            tester.getSemantics(_after(AfterEnd.keepGoing)),
            isSemantics(
              label: _l10n.endActionsAfterKeepGoing,
              hasCheckedState: true,
              isChecked: true,
              isInMutuallyExclusiveGroup: true,
              hasTapAction: true,
            ),
          );
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));

          await tester.tap(_trash);
          await tester.pumpAndSettle();
          expect(tester.getSemantics(_trash), isSemantics(isToggled: true));
          await tester.tap(_after(AfterEnd.closePlayer));
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(_after(AfterEnd.closePlayer)),
            isSemantics(isChecked: true),
          );
          expect(
            tester.getSemantics(_after(AfterEnd.keepGoing)),
            isSemantics(isChecked: false),
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
