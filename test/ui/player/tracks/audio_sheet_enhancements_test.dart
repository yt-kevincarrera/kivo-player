import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/core/theme/kivo_theme.dart';
import 'package:kivo_player/platform/subtitle_finder_provider.dart';
import 'package:kivo_player/player/audio/audio_pipeline.dart';
import 'package:kivo_player/player/audio/audio_pipeline_controller.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/ui/player/tracks/track_picker.dart';
import '../../../fakes/fakes.dart';
import '../../../helpers/pump_app.dart';

final _l10n = l10nFor(const Locale('es'));

Future<ProviderContainer> _open(WidgetTester tester,
    {KivoSettings Function(KivoSettings)? tweak,
    AudioSource? source,
    Size size = const Size(420, 900)}) async {
  final engine = FakePlaybackEngine();
  addTearDown(engine.dispose);
  final s = await SettingsService.load(InMemorySettingsStore());
  if (tweak != null) await s.update(tweak(s.current));
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(s),
    playbackEngineProvider.overrideWithValue(engine),
    subtitleFinderProvider.overrideWithValue(FakeSubtitleFinder()),
  ]);
  addTearDown(c.dispose);
  c.read(currentVideoProvider.notifier).open(const VideoSession(
      playbackPath: '/v/a.mkv', displayName: 'a.mkv', queue: ['/v/a.mkv'], index: 0));
  c.read(currentAudioSourceProvider.notifier).state = source;

  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await pumpLocalized(
    tester,
    Scaffold(
      body: Center(
        child: Consumer(
          builder: (context, ref, _) => ElevatedButton(
            onPressed: () => showAudioPicker(context, ref),
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
  await tester.pump();
  engine.emitAudioTracks(const [
    MediaTrack(id: '1', title: 'Español', language: 'es'),
    MediaTrack(id: '2', title: 'English', language: 'en'),
  ]);
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('both enhancements are offered, off, with what they would do',
      (tester) async {
    await _open(tester, source: const AudioSource(codec: 'ac3', channels: 6));
    // The eyebrow style upper-cases its label, like the sheet's others.
    expect(find.text(_l10n.playerTracksSectionEnhance.toUpperCase()),
        findsOneWidget);
    expect(find.text(_l10n.playerTracksNightMode), findsOneWidget);
    expect(find.text(_l10n.playerTracksNightModeOffHint), findsOneWidget);
    expect(find.text(_l10n.playerTracksVoiceBoostOffHint), findsOneWidget);
  });

  testWidgets('Modo noche on a Dolby track says it is compressing',
      (tester) async {
    await _open(tester,
        tweak: (s) => s.copyWith(nightMode: true),
        source: const AudioSource(codec: 'eac3', channels: 6));
    expect(find.text(_l10n.playerTracksNightModeDolby), findsOneWidget);
  });

  // Asked for by the user: disabled and saying why beats letting it be
  // switched on to do nothing.
  testWidgets('Modo noche is disabled on a non-Dolby track and says why',
      (tester) async {
    final c = await _open(tester,
        source: const AudioSource(codec: 'aac', channels: 2));
    expect(find.text(_l10n.playerTracksNightModeNoEffect), findsOneWidget);
    await tester.tap(find.text(_l10n.playerTracksNightMode));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).nightMode, isFalse,
        reason: 'a disabled card cannot be switched on');
  });

  testWidgets('a night mode already on is not lit on a non-Dolby track',
      (tester) async {
    await _open(tester,
        tweak: (s) => s.copyWith(nightMode: true),
        source: const AudioSource(codec: 'aac', channels: 2));
    expect(find.text(_l10n.playerTracksNightModeNoEffect), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing,
        reason: 'the setting is kept for the next Dolby track, but not shown on');
  });

  testWidgets('while the track is unknown Modo noche waits, disabled',
      (tester) async {
    final c = await _open(tester);
    expect(find.text(_l10n.playerTracksReadingTrack), findsOneWidget);
    await tester.tap(find.text(_l10n.playerTracksNightMode));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).nightMode, isFalse);
  });

  testWidgets('Realzar voces says which of its two methods applies',
      (tester) async {
    await _open(tester,
        tweak: (s) => s.copyWith(voiceBoost: true),
        source: const AudioSource(codec: 'ac3', channels: 6));
    expect(find.text(_l10n.playerTracksVoiceBoostSurround), findsOneWidget);
  });

  testWidgets('tapping toggles in place and the sheet stays open',
      (tester) async {
    final c = await _open(tester,
        source: const AudioSource(codec: 'eac3', channels: 6));
    await tester.tap(find.text(_l10n.playerTracksNightMode));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.playerTracksVoiceBoost));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).nightMode, isTrue);
    expect(c.read(settingsProvider).voiceBoost, isTrue);
    expect(find.text(_l10n.playerTracksNightModeDolby), findsOneWidget);
  });

  testWidgets('Realzar voces does not guess while the track is unknown',
      (tester) async {
    await _open(tester, tweak: (s) => s.copyWith(voiceBoost: true));
    expect(find.text(_l10n.playerTracksEnhancePending), findsOneWidget);
  });

  testWidgets('a stereo track gets the voice-EQ line', (tester) async {
    await _open(tester,
        tweak: (s) => s.copyWith(voiceBoost: true),
        source: const AudioSource(codec: 'aac', channels: 2));
    expect(find.text(_l10n.playerTracksVoiceBoostStereo), findsOneWidget);
  });

  testWidgets('it fits a landscape phone without overflowing', (tester) async {
    await _open(tester, size: const Size(640, 360));
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
        find.text(_l10n.playerTracksVoiceBoost), 100,
        scrollable: find.byType(Scrollable).last);
    expect(find.text(_l10n.playerTracksVoiceBoost), findsOneWidget);
  });
}
