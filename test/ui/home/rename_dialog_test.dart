import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/widgets/rename_dialog.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

const _v = VideoItem(
  id: '1', uri: 'content://v/1', name: 'movie.mp4', folder: 'Movies',
  durationMs: 1000, sizeBytes: 10, dateAddedMs: 0,
);

void main() {
  testWidgets('rename dialog prefills base name, shows extension, validates', (tester) async {
    String? result = 'SENTINEL';
    await pumpLocalized(
      tester,
      Scaffold(body: Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () async { result = await showRenameDialog(context, _v); },
          child: const Text('go'),
        );
      })),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    // Prefills the base name (no extension) and shows the extension suffix.
    expect(find.widgetWithText(TextField, 'movie'), findsOneWidget);
    expect(find.text('.mp4'), findsOneWidget);

    // Clearing the field disables Save.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    final saveBtn = tester.widget<TextButton>(
        find.ancestor(of: find.text(_l10n.commonSave), matching: find.byType(TextButton)));
    expect(saveBtn.onPressed, isNull);

    // A valid new name enables Save and returns the sanitized base.
    await tester.enterText(find.byType(TextField), '  Nueva peli  ');
    await tester.pump();
    await tester.tap(find.text(_l10n.commonSave));
    await tester.pumpAndSettle();
    expect(result, 'Nueva peli');
  });
}
