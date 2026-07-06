import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/ui/home/widgets/folder_grid.dart';
import '../../fakes/fakes.dart';

void main() {
  testWidgets('folder count pill uses the accent, not a hardcoded gold', (t) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(accentColor: 0xFF2D6CFF)); // blue accent
    const item = VideoItem(
      id: '1',
      uri: 'u',
      name: 'a.mkv',
      folder: 'F',
      durationMs: 1000,
      sizeBytes: 1,
      dateAddedMs: 1,
    );
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(s),
      ],
      child: MaterialApp(
        theme: KivoTheme.dark(accent: const Color(0xFF2D6CFF)),
        home: Scaffold(
          body: FolderGrid(videos: const [item], onOpenFolder: (_, __) {}),
        ),
      ),
    ));
    await t.pump();
    // The "1 vid" pill text should be painted with the accent, not gold.
    final txt = findPillText(t);
    expect(txt.style!.color, const Color(0xFF2D6CFF));
  });
}

// Helper: find the count-pill Text ("1 vid"/"N vids").
Text findPillText(WidgetTester t) =>
    t.widget<Text>(find.textContaining('vid'));
