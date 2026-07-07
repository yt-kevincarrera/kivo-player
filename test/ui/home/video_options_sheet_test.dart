import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/widgets/video_options_sheet.dart';

const _v = VideoItem(
  id: '1', uri: 'content://v/1', name: 'clip.mp4', folder: 'Movies',
  durationMs: 1000, sizeBytes: 10, dateAddedMs: 0,
);

void main() {
  testWidgets('VideoOptionsSheet shows four actions and fires callbacks', (tester) async {
    final fired = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VideoOptionsSheet(
          video: _v,
          onShare: () => fired.add('share'),
          onRename: () => fired.add('rename'),
          onDetails: () => fired.add('details'),
          onDelete: () => fired.add('delete'),
        ),
      ),
    ));

    expect(find.text('clip.mp4'), findsOneWidget);
    for (final label in ['Compartir', 'Renombrar', 'Detalles', 'Borrar']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('Compartir'));
    await tester.tap(find.text('Borrar'));
    expect(fired, ['share', 'delete']);
  });
}
