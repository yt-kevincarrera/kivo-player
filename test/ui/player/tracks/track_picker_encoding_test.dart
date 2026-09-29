import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/platform/subtitle_transcoder_provider.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/subtitle_loader.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';
import 'package:kivo_player/ui/player/tracks/track_picker.dart';
import '../../../fakes/fakes.dart';
import '../../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

const _cyrillicDetected = ActiveExternalSubtitle(
    resumeKey: 'ep1.mkv',
    sourceUri: 'content://media/external/file/7',
    title: 'ep1.ru.srt',
    encoding: 'windows-1251',
    detected: true,
    binary: false);

class _H {
  _H(this.c, this.engine, this.transcoder, this.prefs);
  final ProviderContainer c;
  final FakePlaybackEngine engine;
  final FakeSubtitleTranscoder transcoder;
  final InMemoryTrackPrefsStore prefs;
}

Future<_H> _open(WidgetTester tester, {ActiveExternalSubtitle? active}) async {
  final engine = FakePlaybackEngine()
    ..currentSubtitleTrackValue = const MediaTrack(id: '3', title: 'ep1.ru.srt');
  addTearDown(engine.dispose);
  final transcoder = FakeSubtitleTranscoder();
  final prefs = InMemoryTrackPrefsStore();
  final s = await SettingsService.load(InMemorySettingsStore());
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
    subtitleTranscoderProvider.overrideWithValue(transcoder),
    trackPrefsStoreProvider.overrideWithValue(prefs),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(const VideoSession(
      playbackPath: '/v/ep1.mkv',
      displayName: 'ep1.mkv',
      queue: ['/v/ep1.mkv'],
      index: 0));
  c.read(activeExternalSubtitleProvider.notifier).state = active;

  await tester.binding.setSurfaceSize(const Size(420, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await pumpLocalized(
    tester,
    Scaffold(
      body: Center(
        child: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () => showSubtitlePicker(context, ref),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    container: c,
    theme: KivoTheme.dark(),
  );
  await tester.pump();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return _H(c, engine, transcoder, prefs);
}

void main() {
  testWidgets('an active external subtitle shows what it is being read as',
      (tester) async {
    await _open(tester, active: _cyrillicDetected);
    expect(find.text(_l10n.playerTracksEncodingLabel), findsOneWidget);
    expect(
        find.text(_l10n.playerTracksEncodingAutoDetected(_l10n.encodingCyrillic)),
        findsOneWidget);
  });

  testWidgets('no external subtitle, no encoding card', (tester) async {
    await _open(tester);
    expect(find.text(_l10n.playerTracksEncodingLabel), findsNothing);
  });

  testWidgets('a binary subtitle gets no encoding card', (tester) async {
    await _open(tester,
        active: const ActiveExternalSubtitle(
            resumeKey: 'ep1.mkv',
            sourceUri: '/s/movie.sub',
            title: null,
            encoding: null,
            detected: false,
            binary: true));
    expect(find.text(_l10n.playerTracksEncodingLabel), findsNothing);
  });

  testWidgets('picking an encoding reloads the file in it and remembers it',
      (tester) async {
    final h = await _open(tester, active: _cyrillicDetected);
    await tester.tap(find.text(_l10n.playerTracksEncodingLabel));
    await tester.pumpAndSettle();

    expect(find.text(_l10n.playerTracksEncodingSheetTitle), findsOneWidget);
    await tester.scrollUntilVisible(find.text('windows-1253'), 200,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('windows-1253'), findsOneWidget,
        reason: 'the technical name sits under the readable one');
    await tester.tap(find.text(_l10n.encodingGreek));
    await tester.pumpAndSettle();

    expect(h.prefs.forKey('ep1.mkv')!.subtitleEncoding, 'windows-1253');
    expect(h.transcoder.calls.last,
        ('content://media/external/file/7', 'ep1.ru.srt', 'windows-1253'));
    expect(h.engine.subtitleReplaceCount, 1);
    expect(h.c.read(activeExternalSubtitleProvider)!.detected, isFalse);
  });

  testWidgets('"Más…" reveals the system charsets the short list lacks',
      (tester) async {
    await _open(tester, active: _cyrillicDetected);
    await tester.tap(find.text(_l10n.playerTracksEncodingLabel));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(_l10n.playerTracksEncodingMore), 300,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text(_l10n.playerTracksEncodingMore));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('IBM437'), 300,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('IBM437'), findsOneWidget);
    expect(find.text('KOI8-R'), findsOneWidget);
  });
}
