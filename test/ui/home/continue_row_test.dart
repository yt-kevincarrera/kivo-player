import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart'; // resumeServiceProvider
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/home/widgets/continue_row.dart';
import 'package:kivo_player/ui/home/widgets/video_tile.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

class _Granted implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

VideoItem _v(String n, int dur) => VideoItem(
    id: n,
    uri: 'content://$n',
    name: n,
    folder: 'F',
    durationMs: dur,
    sizeBytes: 1,
    dateAddedMs: 0);

ProviderContainer _container(List<VideoItem> items, InMemoryResumeStore store,
    SettingsService settingsSvc) {
  return ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(settingsSvc),
    mediaPermissionImplProvider.overrideWithValue(_Granted()),
    mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(items)),
    resumeServiceProvider.overrideWithValue(ResumeService(store)),
    playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
  ]);
}

void main() {
  testWidgets(
      'long-pressing a continue-watching card opens the shared video options sheet',
      (tester) async {
    final store = InMemoryResumeStore();
    await store.put('clip.mp4', 30, 100); // 30s of 100s = 30% watched

    final settingsSvc = await SettingsService.load(InMemorySettingsStore());
    final container =
        _container([_v('clip.mp4', 100000)], store, settingsSvc);
    addTearDown(container.dispose);
    await container.read(mediaIndexProvider.future); // ensure index loaded

    await pumpLocalized(
      tester,
      Scaffold(body: ContinueRow(onOpen: (_, __) {})),
      container: container,
    );
    await tester.pump();

    expect(find.text('clip.mp4'), findsOneWidget);

    // Long-press the card, not a tap — the row's own onTap must stay untouched.
    await tester.longPress(find.byType(VideoTile));
    await tester.pumpAndSettle();

    // The sheet's header repeats the video name, so it now appears twice:
    // once (invisible, behind the sheet) in the carousel, once in the sheet.
    expect(find.text('clip.mp4'), findsNWidgets(2));
    for (final label in [
      _l10n.commonShare,
      _l10n.commonRename,
      _l10n.videoSheetDetails,
      _l10n.videoSheetMarkWatched,
      _l10n.videoSheetClearResume,
      _l10n.playlistAddToListLabel,
      _l10n.videoSheetMoveToVault,
      _l10n.commonDelete,
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets(
      'a horizontal drag still scrolls the row after long-press wiring',
      (tester) async {
    final store = InMemoryResumeStore();
    final items = <VideoItem>[];
    for (var i = 0; i < 8; i++) {
      // Descending updatedAtMs so v0 sorts first and v7 last — matches
      // continueWatchingProvider's "newest first" ordering.
      await store.put('v$i.mp4', 30, 1000 - i);
      items.add(_v('v$i.mp4', 100000));
    }
    final settingsSvc = await SettingsService.load(InMemorySettingsStore());
    final container = _container(items, store, settingsSvc);
    addTearDown(container.dispose);
    await container.read(mediaIndexProvider.future);

    await pumpLocalized(
      tester,
      Scaffold(body: ContinueRow(onOpen: (_, __) {})),
      container: container,
    );
    await tester.pump();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, 0);

    await tester.drag(find.byType(ListView), const Offset(-600, 0));
    await tester.pump();

    expect(scrollable.position.pixels, greaterThan(0));
  });
}
