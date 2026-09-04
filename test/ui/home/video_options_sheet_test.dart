import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/widgets/video_options_sheet.dart';

const _v = VideoItem(
  id: '1', uri: 'content://v/1', name: 'clip.mp4', folder: 'Movies',
  durationMs: 1000, sizeBytes: 10, dateAddedMs: 0,
);

Widget _sheet({
  List<String>? fired,
  bool isPlayed = false,
  bool hasResume = false,
}) {
  final f = fired ?? <String>[];
  return MaterialApp(
    home: Scaffold(
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
    await tester.pumpWidget(_sheet(fired: fired));

    expect(find.text('clip.mp4'), findsOneWidget);
    for (final label in [
      'Compartir',
      'Renombrar',
      'Detalles',
      'Marcar como visto',
      'Añadir a lista',
      'Mover al Vault',
      'Borrar',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    // No resume position — the "quitar de continuar viendo" row is hidden.
    expect(find.text('Quitar de Continuar viendo'), findsNothing);

    await tester.tap(find.text('Compartir'));
    await tester.tap(find.text('Borrar'));
    expect(fired, ['share', 'delete']);
  });

  testWidgets('played row shows "Marcar como visto" when not played and fires onTogglePlayed',
      (tester) async {
    final fired = <String>[];
    await tester.pumpWidget(_sheet(fired: fired, isPlayed: false));

    expect(find.text('Marcar como visto'), findsOneWidget);
    expect(find.text('Marcar como no visto'), findsNothing);

    await tester.tap(find.text('Marcar como visto'));
    expect(fired, ['togglePlayed']);
  });

  testWidgets('played row shows "Marcar como no visto" when already played',
      (tester) async {
    await tester.pumpWidget(_sheet(isPlayed: true));

    expect(find.text('Marcar como no visto'), findsOneWidget);
    expect(find.text('Marcar como visto'), findsNothing);
  });

  testWidgets('continue row appears only with a resume position and fires onClearResume',
      (tester) async {
    final fired = <String>[];
    await tester.pumpWidget(_sheet(fired: fired, hasResume: true));

    expect(find.text('Quitar de Continuar viendo'), findsOneWidget);
    await tester.tap(find.text('Quitar de Continuar viendo'));
    expect(fired, ['clearResume']);
  });
}
