import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_permission.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/platform/media_permission_provider.dart';
import 'package:kivo_player/platform/frame_extractor_provider.dart';
import 'package:kivo_player/player/library/library_grouping.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/home/widgets/video_density_feed.dart';
import '../../fakes/fakes.dart';

class _GrantedPerm implements MediaPermission {
  @override
  Future<MediaAccess> status() async => MediaAccess.granted;
  @override
  Future<MediaAccess> request() async => MediaAccess.granted;
}

// dateAddedMs = 1 (epoch) → an old "mmm yyyy" section header when grouped by
// day. The exact label depends on the local timezone, so tests derive it from
// [groupByDay] rather than hardcoding a string.
const _videos = [
  VideoItem(
    id: '1',
    uri: 'content://1',
    name: 'Inception.mp4',
    folder: 'Movies',
    durationMs: 90000,
    sizeBytes: 1,
    dateAddedMs: 1,
  ),
  VideoItem(
    id: '2',
    uri: 'content://2',
    name: 'Avatar.mp4',
    folder: 'Downloads',
    durationMs: 120000,
    sizeBytes: 1,
    dateAddedMs: 1,
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required bool groupByDate,
  required bool showContinueRow,
  void Function(VideoItem current, List<VideoItem> all)? onOpen,
}) async {
  final settingsService = await SettingsService.load(InMemorySettingsStore());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(settingsService),
        mediaPermissionImplProvider.overrideWithValue(_GrantedPerm()),
        mediaIndexerProvider.overrideWithValue(FakeMediaIndexer(_videos)),
        resumeServiceProvider.overrideWithValue(
          ResumeService(InMemoryResumeStore()),
        ),
        frameExtractorProvider.overrideWithValue(FakeFrameExtractor()),
        playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
      ],
      child: MaterialApp(
        theme: KivoTheme.light(),
        home: Scaffold(
          body: VideoDensityFeed(
            videos: _videos,
            onOpen: onOpen ?? (_, __) {},
            groupByDate: groupByDate,
            showContinueRow: showContinueRow,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // The label groupByDay assigns to the epoch-timestamped fixtures (single
  // section since both videos share dateAddedMs).
  final dayLabel = groupByDay(_videos, DateTime.now()).first.label;

  testWidgets('flat mode (groupByDate: false) renders no date-section header',
      (tester) async {
    await _pump(tester, groupByDate: false, showContinueRow: false);

    // Videos still show...
    expect(find.text('Inception.mp4'), findsOneWidget);
    expect(find.text('Avatar.mp4'), findsOneWidget);
    // ...but the day header does not.
    expect(find.text(dayLabel), findsNothing);
  });

  testWidgets('grouped mode (groupByDate: true) renders a date-section header',
      (tester) async {
    await _pump(tester, groupByDate: true, showContinueRow: false);

    expect(find.text(dayLabel), findsOneWidget);
  });

  testWidgets('showContinueRow: false hides the "Continuar viendo" strip',
      (tester) async {
    await _pump(tester, groupByDate: false, showContinueRow: false);

    expect(find.text('Continuar viendo'), findsNothing);
  });

  testWidgets('tapping a video title fires onOpen with the right video',
      (tester) async {
    VideoItem? opened;
    List<VideoItem>? all;
    await _pump(
      tester,
      groupByDate: false,
      showContinueRow: false,
      onOpen: (current, list) {
        opened = current;
        all = list;
      },
    );

    await tester.tap(find.text('Inception.mp4'));
    await tester.pump();

    expect(opened?.name, 'Inception.mp4');
    expect(all, _videos);
  });
}
