import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/media_file_ops_provider.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/ui/home/widgets/video_options_sheet.dart';
import '../../fakes/fakes.dart';

const _a = VideoItem(
  id: '1',
  uri: 'u1',
  name: 'a.mp4',
  folder: 'F',
  durationMs: 1,
  sizeBytes: 1,
  dateAddedMs: 0,
);

Future<void> _openAndTapBorrar(
  WidgetTester tester, {
  required bool trash,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mediaFileOpsProvider.overrideWithValue(
          FakeMediaFileOps()..movesToTrash = trash,
        ),
        playedStoreProvider.overrideWithValue(InMemoryPlayedStore()),
        resumeServiceProvider.overrideWithValue(
          ResumeService(InMemoryResumeStore()),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (ctx, ref, _) => Builder(
              builder: (b) => TextButton(
                onPressed: () => showVideoOptions(b, ref, _a),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Borrar'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'on Android 11+ the confirm says trash, not «no se puede deshacer»',
    (tester) async {
      await _openAndTapBorrar(tester, trash: true);
      expect(find.text('Mover a la papelera'), findsWidgets);
      expect(find.textContaining('30 días'), findsOneWidget);
      expect(find.textContaining('no se puede deshacer'), findsNothing);
    },
  );

  testWidgets('below Android 11 the confirm still warns it is permanent', (
    tester,
  ) async {
    await _openAndTapBorrar(tester, trash: false);
    expect(find.text('Borrar video'), findsOneWidget);
    expect(find.textContaining('no se puede deshacer'), findsOneWidget);
  });
}
