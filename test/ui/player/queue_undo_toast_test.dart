import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/queue/queue_undo.dart';
import 'package:kivo_player/ui/player/queue/queue_undo_toast.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

const _session = VideoSession(
  playbackPath: 'content://A/a.mkv', displayName: 'a.mkv',
  queue: ['content://A/a.mkv', 'content://A/b.mkv', 'content://A/c.mkv'],
  queueNames: ['a.mkv', 'b.mkv', 'c.mkv'],
  index: 0,
);

void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [settingsServiceProvider.overrideWithValue(s)]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session);
    await pumpLocalized(
      tester,
      const Scaffold(body: Stack(children: [Positioned.fill(child: QueueUndoToast())])),
      container: c,
    );
    return c;
  }

  testWidgets('nothing while there is nothing to undo', (tester) async {
    await pump(tester);
    expect(find.text(_l10n.commonUndo), findsNothing);
  });

  testWidgets('each edit says what happened', (tester) async {
    final c = await pump(tester);
    final n = c.read(currentVideoProvider.notifier);
    n.remove(2);
    await tester.pump();
    expect(find.text(_l10n.playerQueueRemovedToast), findsOneWidget);
    n.playNext(2);
    await tester.pump();
    expect(find.text(_l10n.playerQueuePlayNextToast), findsOneWidget);
    n.reorder(1, 2);
    await tester.pump();
    expect(find.text(_l10n.playerQueueMovedToast), findsOneWidget);
    await n.setShuffle(true);
    await tester.pump();
    expect(find.text(_l10n.playerQueueShuffleResetToast), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Deshacer puts the order back and closes the toast', (tester) async {
    final c = await pump(tester);
    c.read(currentVideoProvider.notifier).remove(1);
    await tester.pump();
    await tester.tap(find.text(_l10n.commonUndo));
    await tester.pump();
    expect(c.read(currentVideoProvider)!.playOrder, [0, 1, 2]);
    expect(find.text(_l10n.playerQueueRemovedToast), findsNothing);
  });

  testWidgets('goes away by itself after 4 s, keeping the edit', (tester) async {
    final c = await pump(tester);
    c.read(currentVideoProvider.notifier).remove(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3800));
    expect(find.text(_l10n.playerQueueRemovedToast), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text(_l10n.playerQueueRemovedToast), findsNothing);
    expect(c.read(queueUndoProvider), isNull);
    expect(c.read(currentVideoProvider)!.playOrder, [0, 2]);
  });
}
