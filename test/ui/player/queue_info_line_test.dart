import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/queue/queue_info_line.dart';
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

void main() {
  Future<ProviderContainer> pump(WidgetTester tester,
      {VideoSession session = _session, String repeat = 'off'}) async {
    final s = await SettingsService.load(InMemorySettingsStore());
    await s.update(s.current.copyWith(repeatMode: repeat));
    final c = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(s),
      positionProvider.overrideWith((ref) => Stream.value(const Duration(minutes: 10))),
      durationProvider.overrideWith((ref) => Stream.value(const Duration(minutes: 30))),
    ]);
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier).open(session);
    await pumpLocalized(tester, const Scaffold(body: QueueInfoLine()), container: c);
    await tester.pump();
    return c;
  }

  String line(WidgetTester tester) =>
      tester.widget<Text>(find.byType(Text)).data!;

  testWidgets('position, time left and end time', (tester) async {
    await pump(tester);
    final text = line(tester);
    // 20 min left of b + 1 h 30 min of c.
    expect(text, startsWith('${_l10n.playerQueuePosition(2, 3)} · '));
    expect(text, contains(_l10n.playerQueueTimeLeft(_l10n.playerQueueHoursMinutes(1, 50))));
    expect(text, contains('acaba a la'));
  });

  testWidgets('follows the edited play order', (tester) async {
    final c = await pump(tester);
    c.read(currentVideoProvider.notifier).remove(2);
    await tester.pump();
    final text = line(tester);
    expect(text, startsWith(_l10n.playerQueuePosition(2, 2)));
    expect(text, contains(_l10n.playerQueueTimeLeft(_l10n.playerQueueMinutes(20))));
  });

  testWidgets('only the counter under repeat (there is no end)', (tester) async {
    await pump(tester, repeat: 'list');
    expect(line(tester), _l10n.playerQueuePosition(2, 3));
  });

  testWidgets('only the counter when a later duration is unknown', (tester) async {
    await pump(tester, session: const VideoSession(
      playbackPath: 'content://A/b.mkv', displayName: 'b.mkv',
      queue: ['content://A/a.mkv', 'content://A/b.mkv', 'content://A/c.mkv'],
      queueNames: ['a.mkv', 'b.mkv', 'c.mkv'],
      index: 1,
    ));
    expect(line(tester), _l10n.playerQueuePosition(2, 3));
  });
}
