import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/state/library_selection.dart';
import 'package:kivo_player/ui/home/widgets/selection_app_bar.dart';

const _a = VideoItem(id: '1', uri: 'u1', name: 'a.mp4', folder: 'F', durationMs: 1, sizeBytes: 1, dateAddedMs: 0);
const _b = VideoItem(id: '2', uri: 'u2', name: 'b.mp4', folder: 'F', durationMs: 1, sizeBytes: 1, dateAddedMs: 0);

void main() {
  testWidgets('shows count, select-all fills, X clears', (tester) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(librarySelectionProvider.notifier).toggle('u1');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        home: Scaffold(appBar: SelectionAppBar(allVisible: [_a, _b])),
      ),
    ));
    await tester.pump();

    expect(find.text('1 seleccionado'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pump();
    expect(c.read(librarySelectionProvider), {'u1', 'u2'});

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(c.read(librarySelectionProvider), isEmpty);
  });
}
