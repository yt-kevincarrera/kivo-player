import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/player/end_actions/end_actions.dart';
import 'package:kivo_player/player/end_actions/end_flow.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/autoplay/autoplay_overlay.dart';
import 'package:kivo_player/ui/player/state/autoplay_state.dart';
import '../../../fakes/fakes.dart';
import '../../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

void main() {
  const ended = VideoSession(
    playbackPath: 'content://media/1',
    displayName: 'ep1.mkv',
    queue: ['content://media/1', 'content://media/2'],
    queueNames: ['ep1.mkv', 'ep2.mkv'],
    index: 0,
  );
  const item = VideoItem(
    id: '1',
    uri: 'content://media/1',
    name: 'ep1.mkv',
    folder: 'Serie',
    durationMs: 1,
    sizeBytes: 1,
    dateAddedMs: 0,
  );

  Future<ProviderContainer> pumpCard(WidgetTester tester, {bool trashOs = true}) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaFileOpsProvider.overrideWithValue(FakeMediaFileOps()..movesToTrash = trashOs),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(ended);
    await pumpLocalized(tester, const Scaffold(body: AutoplayOverlay()), container: c);
    return c;
  }

  testWidgets('an action countdown shows its label and confirms after 3 s',
      (tester) async {
    final c = await pumpCard(tester);
    c.read(afterPendingProvider.notifier).state = AfterEnd.closeApp;
    await tester.pump();
    expect(find.text(_l10n.endActionsCountdownCloseApp), findsOneWidget);
    expect(find.text('ep1.mkv'), findsOneWidget);
    expect(find.text(_l10n.endActionsNow), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(c.read(afterConfirmProvider), isTrue);
  });

  testWidgets('«Ahora» confirms at once', (tester) async {
    final c = await pumpCard(tester);
    c.read(afterPendingProvider.notifier).state = AfterEnd.screenOff;
    await tester.pump();
    await tester.tap(find.text(_l10n.endActionsNow));
    await tester.pump();
    expect(c.read(afterConfirmProvider), isTrue);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('the trash line shows, and «Conservar» drops only the trash',
      (tester) async {
    final c = await pumpCard(tester);
    c.read(endTrashProvider.notifier).state = const EndTrash(ended, item);
    c.read(autoplayPendingProvider.notifier).state =
        c.read(currentVideoProvider.notifier).sessionAt(1);
    await tester.pump();
    expect(find.text(_l10n.endActionsCardTrashLine), findsOneWidget);

    await tester.tap(find.text(_l10n.endActionsKeep));
    await tester.pump();
    expect(c.read(endTrashProvider), isNull);
    expect(c.read(autoplayPendingProvider), isNotNull);
    expect(find.text(_l10n.endActionsCardTrashLine), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('without a system trash the line says the file is deleted',
      (tester) async {
    final c = await pumpCard(tester, trashOs: false);
    c.read(endTrashProvider.notifier).state = const EndTrash(ended, item);
    c.read(afterPendingProvider.notifier).state = AfterEnd.closePlayer;
    await tester.pump();
    expect(find.text(_l10n.endActionsCardDeleteLine), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('«Cancelar» clears the countdown and the planned trash', (tester) async {
    final c = await pumpCard(tester);
    c.read(endTrashProvider.notifier).state = const EndTrash(ended, item);
    c.read(afterPendingProvider.notifier).state = AfterEnd.closePlayer;
    await tester.pump();
    await tester.tap(find.text(_l10n.commonCancel));
    await tester.pump();
    expect(c.read(afterPendingProvider), isNull);
    expect(c.read(endTrashProvider), isNull);
    await tester.pump(const Duration(seconds: 4));
    expect(c.read(afterConfirmProvider), isFalse);
  });
}
