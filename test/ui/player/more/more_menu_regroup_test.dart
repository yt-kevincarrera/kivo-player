// Covers the 2026-09 regroup of the ⋮ menu: the four action tiles, the two
// inline segmented controls (Repetir / Aleatorio), and the 640×360 landscape
// fit. Marcar aquí, Temporizador and Sincronizar already have their own
// dedicated coverage (more_menu_bookmark_test.dart,
// sleep_timer_panel_test.dart, track_sync_entry_test.dart) — this file adds
// what those don't: Capturar, the segmented controls, and the layout budget.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/more/more_menu.dart';
import '../../../fakes/fakes.dart';

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: '/v/a.mkv',
        displayName: 'a.mkv',
        queue: ['/v/a.mkv'],
        index: 0,
      ));

  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: KivoTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => showMoreMenu(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('Capturar tile triggers a capture attempt and reports it', (tester) async {
    await _pump(tester);

    // No frame extractor/image saver is wired for this test, so the capture
    // itself fails — the point here is only that the tile's tap reached
    // FrameCaptureController.capture() and the outcome was reported, not
    // that the capture succeeded (that's frame_capture_controller_test.dart's
    // job).
    await tester.tap(find.text('Capturar'));
    await tester.pumpAndSettle();

    expect(find.text('Detalles'), findsOneWidget); // the failure SnackBar's action
  });

  testWidgets('tapping a Repetir segment writes the mode and leaves the sheet open',
      (tester) async {
    final c = await _pump(tester);
    expect(c.read(settingsProvider).repeatMode, 'off');

    await tester.tap(find.text('Lista'));
    await tester.pump();

    expect(c.read(settingsProvider).repeatMode, 'list');
    // Sheet is still up: its caption and the next group are still visible.
    expect(find.text('Reproducción'), findsOneWidget);
    expect(find.text('Bucle A-B'), findsOneWidget);

    await tester.tap(find.text('Video'));
    await tester.pump();
    expect(c.read(settingsProvider).repeatMode, 'video');
    expect(find.text('Reproducción'), findsOneWidget);
  });

  testWidgets('the Aleatorio toggle flips settings.shuffle and leaves the sheet open',
      (tester) async {
    final c = await _pump(tester);
    expect(c.read(settingsProvider).shuffle, isFalse);

    await tester.tap(find.text('Sí'));
    await tester.pumpAndSettle();

    expect(c.read(settingsProvider).shuffle, isTrue);
    expect(find.text('Reproducción'), findsOneWidget);

    // 'No' also labels the Repetir row's off segment, right above this one —
    // the Aleatorio row's is the second (last) match.
    await tester.tap(find.text('No').last);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).shuffle, isFalse);
  });

  /// Resizes the test viewport, opens the menu, asserts no build-time error
  /// (a RenderFlex overflow reports one, and would fail the test on its own
  /// via FlutterError.onError — asserting it explicitly just gives a clear
  /// point of failure and somewhere for the overflow amount to show up),
  /// and prints the measured content height against the sheet's height
  /// budget for that viewport (landscape — width > height — gets the 0.92
  /// cap; portrait keeps 0.8).
  Future<void> measure(WidgetTester tester, double width, double height) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;

    await _pump(tester);

    expect(tester.takeException(), isNull);

    final contentSize = tester.getSize(find.byKey(const Key('more-menu-content')));
    final capFraction = width > height ? 0.92 : 0.8;
    final maxHeight = height * capFraction;
    // The column sits inside the sheet's ConstrainedBox (maxHeight above)
    // plus its own 14 (top) + 24 (bottom) padding, so this is the true
    // budget the content has to fit inside without scrolling.
    final budget = maxHeight - 14 - 24;
    // Landscape is the case the two-column layout exists for: it has to FIT.
    // Portrait at 360x640 is allowed to scroll (that was always its deal).
    if (width > height) {
      expect(
        contentSize.height,
        lessThanOrEqualTo(budget),
        reason: 'the two-column menu must fit a landscape sheet without scrolling',
      );
    }
    // ignore: avoid_print
    print(
      'more-menu content height at ${width.toInt()}x${height.toInt()}: '
      '${contentSize.height} px (budget $budget px inside a '
      '${maxHeight}px sheet cap, factor $capFraction)',
    );
  }

  testWidgets('the menu fits a 640x360 landscape viewport (two columns, 0.92 cap)',
      (tester) async {
    await measure(tester, 640, 360);
    expect(find.text('Sincronizar'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
  });

  testWidgets('the menu renders without overflow at 800x360 (taller-aspect landscape)',
      (tester) async {
    await measure(tester, 800, 360);
    expect(find.text('Sincronizar'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
  });

  testWidgets('the menu still renders as a single column at 360x640 portrait',
      (tester) async {
    await measure(tester, 360, 640);
    expect(find.text('Sincronizar'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
  });

  testWidgets('the menu still renders as a single column at 360x800 portrait',
      (tester) async {
    await measure(tester, 360, 800);
    expect(find.text('Sincronizar'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
  });
}
