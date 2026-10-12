import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/queue/queue_order.dart';
import 'package:kivo_player/ui/player/controls/time_label.dart';
import '../../fakes/fakes.dart';
import '../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

const _session = VideoSession(
  playbackPath: 'content://A/b.mkv', displayName: 'b.mkv',
  queue: ['content://A/a.mkv', 'content://A/b.mkv', 'content://A/c.mkv'],
  queueNames: ['a.mkv', 'b.mkv', 'c.mkv'],
  // b: 30 min, c: 1 h 30 min.
  queueDurationsMs: [600000, 1800000, 5400000],
  index: 1,
);

const _single = VideoSession(
  playbackPath: 'content://A/b.mkv', displayName: 'b.mkv',
  queue: ['content://A/b.mkv'], queueNames: ['b.mkv'],
  queueDurationsMs: [1800000], index: 0,
);

void main() {
  group('timeToEnd', () {
    ({Duration left, bool queue}) at(VideoSession? s,
            {RepeatMode repeat = RepeatMode.off, double rate = 1}) =>
        timeToEnd(
          session: s,
          repeat: repeat,
          total: const Duration(minutes: 30),
          position: const Duration(minutes: 10),
          rate: rate,
        );

    test('with a queue: the rest of this video plus the ones after it', () {
      expect(at(_session), (left: const Duration(minutes: 110), queue: true));
    });

    test('a single video: the rest of it, at playback speed', () {
      expect(at(_single, rate: 2),
          (left: const Duration(minutes: 10), queue: false));
    });

    test('a repeating queue has no end: falls back to this video', () {
      expect(at(_session, repeat: RepeatMode.list),
          (left: const Duration(minutes: 20), queue: false));
    });

    test('a later duration unknown: falls back to this video', () {
      const s = VideoSession(
        playbackPath: 'content://A/b.mkv', displayName: 'b.mkv',
        queue: ['content://A/b.mkv', 'content://A/c.mkv'],
        queueNames: ['b.mkv', 'c.mkv'], queueDurationsMs: [1800000, 0],
        index: 0,
      );
      expect(at(s), (left: const Duration(minutes: 20), queue: false));
    });
  });

  group('TimeLabel', () {
    Future<void> pump(WidgetTester tester, VideoSession session) async {
      final s = await SettingsService.load(InMemorySettingsStore());
      final c = ProviderContainer(overrides: [
        settingsServiceProvider.overrideWithValue(s),
      ]);
      addTearDown(c.dispose);
      c.read(currentVideoProvider.notifier).open(session);
      await pumpLocalized(
        tester,
        const Scaffold(
          body: TimeLabel(
            total: Duration(minutes: 30),
            position: Duration(minutes: 10),
          ),
        ),
        container: c,
      );
      await tester.pump();
    }

    String text(WidgetTester tester) =>
        tester.widget<Text>(find.byType(Text)).data!;

    testWidgets('a tap cycles length → time left → end time → length',
        (tester) async {
      await pump(tester, _single);
      expect(text(tester), '30:00');
      await tester.tap(find.byType(TimeLabel));
      await tester.pump();
      expect(text(tester), '-20:00');
      await tester.tap(find.byType(TimeLabel));
      await tester.pump();
      expect(text(tester), startsWith(_l10n.playerEndsAtShort('')));
      await tester.tap(find.byType(TimeLabel));
      await tester.pump();
      expect(text(tester), '30:00');
    });

    testWidgets('with a queue the end time is the queue\'s', (tester) async {
      await pump(tester, _session);
      await tester.tap(find.byType(TimeLabel));
      await tester.pump();
      await tester.tap(find.byType(TimeLabel));
      await tester.pump();
      expect(text(tester), startsWith(_l10n.playerQueueEndsAtShort('')));
    });
  });
}
