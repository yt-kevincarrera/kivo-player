import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/media_indexer_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/queue/queue_strip.dart';
import '../../fakes/fakes.dart';

const _session = VideoSession(
  playbackPath: 'content://A/b.mkv', displayName: 'b.mkv',
  queue: ['content://A/a.mkv', 'content://A/b.mkv'],
  queueNames: ['a.mkv', 'b.mkv'], queueIds: ['ida', 'idb'], index: 1, folder: 'A',
);

void main() {
  testWidgets('queue-strip AHORA ribbon uses the accent fill', (t) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(accentColor: 0xFF2D6CFF));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      mediaIndexerProvider.overrideWithValue(FakeMediaIndexer()),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(_session);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: KivoTheme.dark(accent: const Color(0xFF2D6CFF)),
        home: const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: QueueStrip()))),
    ));
    await t.pump();
    // The "AHORA" ribbon container is filled with the accent (blue), not gold.
    final ribbon = t.widget<Container>(find.ancestor(
        of: find.text('AHORA'), matching: find.byType(Container)).first);
    final deco = ribbon.color ?? (ribbon.decoration as BoxDecoration?)?.color;
    expect(deco, const Color(0xFF2D6CFF));
  });
}
