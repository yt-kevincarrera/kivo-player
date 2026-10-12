import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/all_files_access_provider.dart';
import 'package:kivo_player/platform/interfaces/media_file_ops.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/player/bookmarks/bookmark_store.dart';
import 'package:kivo_player/player/end_actions/end_flow.dart';
import 'package:kivo_player/player/end_actions/pending_trash.dart';
import 'package:kivo_player/player/end_actions/trash_queue.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/home/pending_trash.dart';
import 'package:kivo_player/ui/player/state/mini_player_state.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

class _Perm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

PendingTrash _p(String n, int at) =>
    PendingTrash(uri: 'content://media/$n', name: '$n.mkv', id: n, stagedAtMs: at);

void main() {
  late FakeMediaFileOps ops;
  late FakeAllFilesAccess access;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required List<PendingTrash> pending,
    required void Function(BuildContext, WidgetRef) onTap,
    bool granted = false,
  }) async {
    ops = FakeMediaFileOps()..movesToTrash = true;
    access = FakeAllFilesAccess(granted: granted);
    final store = InMemoryPendingTrashStore();
    for (final p in pending) {
      await store.put(p);
    }
    final s = await SettingsService.load(InMemorySettingsStore());
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaFileOpsProvider.overrideWithValue(ops),
      allFilesAccessProvider.overrideWithValue(access),
      pendingTrashStoreProvider.overrideWithValue(store),
      resumeServiceProvider.overrideWithValue(ResumeService(InMemoryResumeStore())),
      playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
      mediaPermissionImplProvider.overrideWithValue(_Perm()),
      bookmarkStoreProvider.overrideWithValue(InMemoryBookmarkStore()),
    ]);
    addTearDown(c.dispose);
    await pumpLocalized(
      tester,
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => onTap(context, ref),
            child: const Text('go'),
          ),
        ),
      ),
      container: c,
    );
    return c;
  }

  testWidgets('the sheet lists what is pending; «Mover» deletes them in one go',
      (tester) async {
    final c = await pump(tester,
        pending: [_p('a', 1), _p('b', 2)], onTap: askAboutPendingTrash);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.pendingTrashTitle(2)), findsOneWidget);
    expect(find.text('a.mkv'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pending-trash-move')));
    await tester.pumpAndSettle();
    expect(ops.deletedManyUris, [
      ['content://media/a', 'content://media/b']
    ]);
    expect(c.read(trashQueueProvider), isEmpty);
    expect(find.text(_l10n.selectionTrashedSnackbar(2)), findsOneWidget);
  });

  testWidgets('«Conservar» forgets them without deleting', (tester) async {
    final c = await pump(tester, pending: [_p('a', 1)], onTap: askAboutPendingTrash);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pending-trash-keep')));
    await tester.pumpAndSettle();
    expect(ops.deletedManyUris, isEmpty);
    expect(c.read(trashQueueProvider), isEmpty);
  });

  testWidgets('with all-files access nothing is asked: they just go', (tester) async {
    await pump(tester,
        pending: [_p('a', 1)], onTap: askAboutPendingTrash, granted: true);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.pendingTrashTitle(1)), findsNothing);
    expect(ops.deletedManyUris, [
      ['content://media/a']
    ]);
  });

  testWidgets('leaving the player flushes all but the video still in the mini-bar',
      (tester) async {
    final c = await pump(tester,
        pending: [_p('a', 1), _p('b', 2)], onTap: flushPendingTrash);
    c.read(currentVideoProvider.notifier).open(const VideoSession(
        playbackPath: 'content://media/b',
        displayName: 'b.mkv',
        queue: ['content://media/b'],
        index: 0));
    c.read(playerMinimizedProvider.notifier).state = true;
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(ops.deletedManyUris, [
      ['content://media/a']
    ]);
    expect(c.read(trashQueueProvider).map((e) => e.uri), ['content://media/b']);
  });

  testWidgets('no flush while Kivo is closing itself', (tester) async {
    final c = await pump(tester, pending: [_p('a', 1)], onTap: flushPendingTrash);
    c.read(suppressTrashFlushProvider.notifier).state = true;
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(ops.deletedManyUris, isEmpty);
  });

  testWidgets('a failed delete is reported with its code', (tester) async {
    await pump(tester, pending: [_p('a', 1)], onTap: flushPendingTrash);
    ops.deleteManyResult = FileOpStatus.error;
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
