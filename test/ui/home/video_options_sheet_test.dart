import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/widgets/video_options_sheet.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

const _v = VideoItem(
  id: '1', uri: 'content://v/1', name: 'clip.mp4', folder: 'Movies',
  durationMs: 1000, sizeBytes: 10, dateAddedMs: 0,
);

Future<void> _pumpSheet(
  WidgetTester tester, {
  List<String>? fired,
  bool isPlayed = false,
  bool hasResume = false,
}) {
  final f = fired ?? <String>[];
  return pumpLocalized(
    tester,
    Scaffold(
      body: VideoOptionsSheet(
        video: _v,
        onShare: () => f.add('share'),
        onRename: () => f.add('rename'),
        onDetails: () => f.add('details'),
        onAddToPlaylist: () => f.add('addToPlaylist'),
        onDelete: () => f.add('delete'),
        onMoveToVault: () => f.add('vault'),
        isPlayed: isPlayed,
        onTogglePlayed: () => f.add('togglePlayed'),
        hasResume: hasResume,
        onClearResume: () => f.add('clearResume'),
      ),
    ),
  );
}

void main() {
  testWidgets('VideoOptionsSheet shows seven actions and fires callbacks', (tester) async {
    final fired = <String>[];
    await _pumpSheet(tester, fired: fired);

    expect(find.text('clip.mp4'), findsOneWidget);
    for (final label in [
      _l10n.commonShare,
      _l10n.commonRename,
      _l10n.videoSheetDetails,
      _l10n.videoSheetMarkWatched,
      _l10n.playlistAddToListLabel,
      _l10n.videoSheetMoveToVault,
      _l10n.commonDelete,
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    // No resume position — the "quitar de continuar viendo" row is hidden.
    expect(find.text(_l10n.videoSheetClearResume), findsNothing);

    await tester.tap(find.text(_l10n.commonShare));
    await tester.tap(find.text(_l10n.commonDelete));
    expect(fired, ['share', 'delete']);
  });

  testWidgets('played row shows "Marcar como visto" when not played and fires onTogglePlayed',
      (tester) async {
    final fired = <String>[];
    await _pumpSheet(tester, fired: fired, isPlayed: false);

    expect(find.text(_l10n.videoSheetMarkWatched), findsOneWidget);
    expect(find.text(_l10n.videoSheetMarkUnwatched), findsNothing);

    await tester.tap(find.text(_l10n.videoSheetMarkWatched));
    expect(fired, ['togglePlayed']);
  });

  testWidgets('played row shows "Marcar como no visto" when already played',
      (tester) async {
    await _pumpSheet(tester, isPlayed: true);

    expect(find.text(_l10n.videoSheetMarkUnwatched), findsOneWidget);
    expect(find.text(_l10n.videoSheetMarkWatched), findsNothing);
  });

  testWidgets('continue row appears only with a resume position and fires onClearResume',
      (tester) async {
    final fired = <String>[];
    await _pumpSheet(tester, fired: fired, hasResume: true);

    expect(find.text(_l10n.videoSheetClearResume), findsOneWidget);
    await tester.tap(find.text(_l10n.videoSheetClearResume));
    expect(fired, ['clearResume']);
  });
}
