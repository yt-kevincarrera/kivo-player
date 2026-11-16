import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/player/library/media_index.dart';
import 'package:kivo_player/player/library/tv_library.dart';
import 'package:kivo_player/player/playlists/playlist_controller.dart';
import 'package:kivo_player/ui/tv/tv_input_mode.dart';
import 'package:kivo_player/ui/tv/tv_playlists.dart';
import '../../helpers/pump_app.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets(
    'TV creates a playlist, adds mounted videos and reorders without drag gestures',
    (t) async {
      t.view.physicalSize = const Size(1280, 720);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final settings = await SettingsService.load(InMemorySettingsStore());
      final videos = List.generate(
        2,
        (i) => VideoItem(
          id: '$i',
          uri: 'file:///drive/$i.avi',
          name: 'Episode $i.avi',
          folder: 'Series',
          durationMs: 10000,
          sizeBytes: 1,
          dateAddedMs: 0,
        ),
      );
      final c = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWithValue(settings),
          tvLibraryIndexProvider.overrideWithValue(AsyncData(videos)),
          mediaIndexProvider.overrideWith(() => _Index(videos)),
        ],
      );
      addTearDown(c.dispose);
      final l = l10nFor(const Locale('es'));
      await pumpLocalized(
        t,
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(40),
            child: TvPlaylists(query: ''),
          ),
        ),
        container: c,
        appBuilder: (_, child) => TvInputMode(enabled: true, child: child!),
      );
      await t.pumpAndSettle();
      await t.tap(find.text(l.playlistNewListLabel));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Series');
      await t.tap(find.text(l.commonSave));
      await t.pumpAndSettle();
      expect(c.read(playlistsProvider).single.name, 'Series');
      await t.tap(find.text('Series'));
      await t.pumpAndSettle();
      for (final video in videos) {
        await t.tap(find.text(l.tvOptions));
        await t.pumpAndSettle();
        await t.tap(find.text(l.playlistAddToListLabel));
        await t.pumpAndSettle();
        await t.tap(find.text(video.name).last);
        await t.pumpAndSettle();
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
      }
      expect(c.read(playlistsProvider).single.entries.map((e) => e.mediaId), [
        '0',
        '1',
      ]);
      await t.tap(find.bySemanticsLabel('${l.tvOptions}: ${videos.last.name}'));
      await t.pumpAndSettle();
      await t.tap(find.text(l.tvMoveEarlier));
      await t.pumpAndSettle();
      expect(c.read(playlistsProvider).single.entries.map((e) => e.mediaId), [
        '1',
        '0',
      ]);
      expect(find.byType(BottomSheet), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}

class _Index extends MediaIndexNotifier {
  _Index(this.videos);
  final List<VideoItem> videos;
  @override
  Future<List<VideoItem>> build() async => videos;
}
