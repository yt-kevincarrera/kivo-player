import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/all_files_access_provider.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/end_actions/end_flow.dart';
import 'package:kivo_player/player/end_actions/pending_trash.dart';
import 'package:kivo_player/player/end_actions/trash_queue.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/end_actions/end_actions_chip.dart';
import 'package:kivo_player/ui/player/end_actions/end_actions_panel.dart';
import 'package:kivo_player/ui/player/end_actions/trash_undo_toast.dart';
import '../../../fakes/fakes.dart';
import '../../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

class _Perm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

const _item = VideoItem(
  id: '1',
  uri: 'content://media/1',
  name: 'ep1.mkv',
  folder: 'Serie',
  durationMs: 1,
  sizeBytes: 1,
  dateAddedMs: 0,
);

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget child, {
    bool inLibrary = true,
    String? repeatMode,
  }) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    if (repeatMode != null) {
      await s.update(s.current.copyWith(repeatMode: repeatMode));
    }
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaFileOpsProvider.overrideWithValue(FakeMediaFileOps()..movesToTrash = true),
      allFilesAccessProvider.overrideWithValue(FakeAllFilesAccess()),
      pendingTrashStoreProvider.overrideWithValue(InMemoryPendingTrashStore()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer([_item])),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
    ]);
    addTearDown(c.dispose);
    await c.read(mediaIndexProvider.future);
    c.read(currentVideoProvider.notifier).open(VideoSession(
      playbackPath: inLibrary ? _item.uri : '/cache/picked.mp4',
      displayName: 'ep1.mkv',
      queue: [inLibrary ? _item.uri : '/cache/picked.mp4'],
      index: 0,
    ));
    await pumpLocalized(tester, Scaffold(body: child), container: c);
    return c;
  }

  group('chip', () {
    testWidgets('hidden until something is armed', (tester) async {
      final c = await pump(tester, const Center(child: EndActionsChip()));
      expect(find.byKey(const Key('end-actions-chip')), findsNothing);
      c.read(endActionsProvider.notifier).setTrash(true);
      await tester.pump();
      expect(find.byKey(const Key('end-actions-chip')), findsOneWidget);
      expect(find.text(_l10n.endActionsSummaryTrash), findsOneWidget);
    });

    testWidgets('summarises both, and ✕ turns everything off', (tester) async {
      final c = await pump(tester, const Center(child: EndActionsChip()));
      c.read(endActionsProvider.notifier)
        ..setTrash(true)
        ..setAfter(AfterEnd.closeApp);
      await tester.pump();
      expect(
          find.text(_l10n.endActionsSummaryBoth(
              _l10n.endActionsSummaryTrash, _l10n.endActionsAfterCloseApp)),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('end-actions-chip-off')));
      await tester.pump();
      expect(c.read(endActionsProvider).isActive, isFalse);
      expect(find.byKey(const Key('end-actions-chip')), findsNothing);
    });
  });

  group('panel', () {
    testWidgets('global toggle saves choices and switches the mode off', (tester) async {
      final c = await pump(tester, const EndActionsPanel());
      await tester.tap(find.byKey(const Key('end-trash-switch')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('end-global-switch')));
      await tester.pump();
      expect(c.read(settingsProvider).endActionsGlobal, isTrue);
      expect(c.read(settingsProvider).endActionsTrash, isTrue);
      await tester.tap(find.byKey(const Key('end-global-switch')));
      await tester.pump();
      expect(c.read(endActionsProvider).isActive, isFalse);
      expect(c.read(settingsProvider).endActionsTrash, isTrue);
    });

    testWidgets('global editor configures trash without an eligible video', (tester) async {
      final c = await pump(tester,
          const EndActionsPanel(globalSettings: true), inLibrary: false);
      await tester.tap(find.byKey(const Key('end-trash-switch')));
      await tester.pump();
      expect(c.read(settingsProvider).endActionsTrash, isTrue);
      expect(c.read(endActionsProvider).isActive, isFalse);
      expect(find.byKey(const Key('end-finish-now')), findsNothing);
      expect(find.byKey(const Key('end-trash-and-next')), findsNothing);
    });

    testWidgets('restart is selectable and explains why trash is blocked', (tester) async {
      final c = await pump(tester, const EndActionsPanel());
      await c.read(endActionsProvider.notifier).setTrash(true);
      await tester.pump();
      final restart = find.byKey(const Key('end-after-restart'));
      await tester.ensureVisible(restart);
      await tester.tap(restart);
      await tester.pump();
      expect(c.read(endActionsProvider).after, AfterEnd.restart);
      expect(c.read(endActionsProvider).trash, isFalse);
      expect(find.text(_l10n.endActionsTrashRestart), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const Key('end-trash-switch'))).onChanged, isNull);
    });

    testWidgets('turns trash on and picks the action', (tester) async {
      final c = await pump(tester, const EndActionsPanel());
      await tester.tap(find.byKey(const Key('end-trash-switch')));
      await tester.pump();
      expect(c.read(endActionsProvider).trash, isTrue);
      await tester.tap(find.byKey(const Key('end-after-screenOff')));
      await tester.pump();
      expect(c.read(endActionsProvider).after, AfterEnd.screenOff);
    });

    testWidgets('a video outside the library cannot be trashed, and says why',
        (tester) async {
      final c = await pump(tester, const EndActionsPanel(), inLibrary: false);
      expect(find.text(_l10n.endActionsTrashNotLibrary), findsOneWidget);
      await tester.tap(find.byKey(const Key('end-trash-switch')));
      await tester.pump();
      expect(c.read(endActionsProvider).trash, isFalse);
      expect(find.byKey(const Key('end-trash-and-next')), findsNothing);
    });

    testWidgets('Repetir: video blocks the trash, and says why', (tester) async {
      await pump(tester, const EndActionsPanel(), repeatMode: 'video');
      expect(find.text(_l10n.endActionsTrashRepeatVideo), findsOneWidget);
    });

    testWidgets('«Terminar ya» is off until something is armed, then fires',
        (tester) async {
      final c = await pump(tester, const EndActionsPanel());
      final finish = find.byKey(const Key('end-finish-now'));
      expect(tester.widget<ButtonStyleButton>(finish).onPressed, isNull);
      c.read(endActionsProvider.notifier).setAfter(AfterEnd.closePlayer);
      await tester.pump();
      expect(tester.widget<ButtonStyleButton>(finish).onPressed, isNotNull);
    });

    testWidgets('«Papelera y siguiente» is offered with the mode off', (tester) async {
      final c = await pump(tester, const EndActionsPanel());
      expect(find.text(_l10n.endActionsTrashAndNext), findsOneWidget);
      c.read(endActionsProvider.notifier).setTrash(true);
      await tester.pump();
      expect(find.text(_l10n.endActionsTrashAndNext), findsNothing);
    });

    testWidgets('«Papelera y siguiente» asks the player for it', (tester) async {
      final c = await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showEndActionsPanel(context),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('end-trash-and-next')));
      await tester.tap(find.byKey(const Key('end-trash-and-next')));
      await tester.pumpAndSettle();
      expect(c.read(trashAndNextProvider), 1);
    });
  });

  group('undo toast', () {
    testWidgets('says where it goes and undoes', (tester) async {
      final c = await pump(tester, const TrashUndoToast());
      c.listen(trashQueueProvider, (_, _) {});
      await c.read(trashQueueProvider.notifier).stage(_item);
      await tester.pump();
      expect(find.text(_l10n.trashUndoOnExit), findsOneWidget);
      await tester.tap(find.text(_l10n.commonUndo));
      await tester.pump();
      expect(c.read(trashQueueProvider), isEmpty);
      expect(find.text(_l10n.trashUndoOnExit), findsNothing);
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
