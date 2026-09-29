import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/error_log_provider.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/decoder/decoder_controller.dart';
import 'package:kivo_player/player/decoder/decoder_mode.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';

import '../../fakes/fakes.dart';

VideoSession _s(String name) => VideoSession(
    playbackPath: '/v/$name', displayName: name, queue: ['/v/$name'], index: 0);

class _Harness {
  _Harness(this.c, this.engine, this.store, this.log);
  final ProviderContainer c;
  final FakePlaybackEngine engine;
  final InMemoryTrackPrefsStore store;
  final ErrorLog log;
  DecoderController get ctl => c.read(decoderControllerProvider);
}

Future<_Harness> _harness({KivoSettings Function(KivoSettings)? tweak}) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  if (tweak != null) await svc.update(tweak(svc.current));
  final engine = FakePlaybackEngine();
  final store = InMemoryTrackPrefsStore();
  final log = ErrorLog(InMemoryErrorLogStore(), appVersion: 't', androidSdk: 0);
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    playbackEngineProvider.overrideWithValue(engine),
    trackPrefsStoreProvider.overrideWithValue(store),
    errorLogProvider.overrideWithValue(log),
  ]);
  return _Harness(c, engine, store, log);
}

void main() {
  group('hwdec on every open', () {
    test('auto writes auto-safe, a software override writes no', () async {
      final h = await _harness();
      addTearDown(h.c.dispose);
      await h.store.put('b.mkv', const VideoTrackPrefs(decoder: 'sw'));

      await h.ctl.open(_s('a.mkv'));
      await h.ctl.open(_s('b.mkv'));
      expect(h.engine.hwdecWrites, ['auto-safe', 'no']);
    });

    // hwdec survives loadfile on the singleton player: a video without an
    // override must actively undo the previous video's software mode.
    test('open A in software, then B without an override → B is reset', () async {
      final h = await _harness();
      addTearDown(h.c.dispose);
      await h.store.put('a.mkv', const VideoTrackPrefs(decoder: 'sw'));

      await h.ctl.open(_s('a.mkv'));
      await h.ctl.open(_s('b.mkv'));
      expect(h.engine.hwdecWrites.last, 'auto-safe');
    });

    test('a global software default applies to videos without an override',
        () async {
      final h = await _harness(tweak: (s) => s.copyWith(decoderMode: 'sw'));
      addTearDown(h.c.dispose);
      await h.ctl.open(_s('a.mkv'));
      expect(h.engine.hwdecWrites, ['no']);
    });
  });

  group('open failure', () {
    test('hardware failing to open retries once in software and remembers it',
        () async {
      final h = await _harness();
      addTearDown(h.c.dispose);
      var calls = 0;
      h.engine.openHook = (_) {
        calls++;
        if (calls == 1) throw StateError('mediacodec init');
      };

      await h.ctl.open(_s('a.mkv'), startAt: const Duration(seconds: 42));

      expect(h.engine.hwdecWrites, ['auto-safe', 'no']);
      expect(h.engine.openCount, 1, reason: 'the retry is the one that opened');
      expect(h.engine.openedAt, const Duration(seconds: 42));
      expect(h.store.forKey('a.mkv')!.decoder, 'sw');
      expect(h.log.entries().single.code, 'KV-504');
      expect(h.c.read(decoderFallbackEventProvider)?.resumeKey, 'a.mkv');
    });

    test('failing in software too is still a KV-501, with no fallback saved',
        () async {
      final h = await _harness();
      addTearDown(h.c.dispose);
      h.engine.openError = StateError('corrupt');

      await expectLater(h.ctl.open(_s('a.mkv')),
          throwsA(isA<KivoFailure>().having((f) => f.op, 'op', KivoOp.openVideo)));
      expect(h.store.forKey('a.mkv'), isNull);
      expect(h.c.read(decoderFallbackEventProvider), isNull);
    });

    test('with automatic switching off, a failure is reported straight away',
        () async {
      final h = await _harness(tweak: (s) => s.copyWith(decoderAutoFallback: false));
      addTearDown(h.c.dispose);
      h.engine.openError = StateError('mediacodec init');

      await expectLater(h.ctl.open(_s('a.mkv')), throwsA(isA<KivoFailure>()));
      expect(h.engine.hwdecWrites, ['auto-safe']);
    });

    test('a video forced to hardware never retries in software', () async {
      final h = await _harness(tweak: (s) => s.copyWith(decoderMode: 'hw'));
      addTearDown(h.c.dispose);
      h.engine.openError = StateError('mediacodec init');

      await expectLater(h.ctl.open(_s('a.mkv')), throwsA(isA<KivoFailure>()));
      expect(h.engine.hwdecWrites, ['auto-safe']);
    });
  });

  group('stall watchdog', () {
    test('no frame for the configured time switches to software live', () {
      fakeAsync((t) {
        late _Harness h;
        _harness().then((v) => h = v);
        t.flushMicrotasks();
        h.ctl.open(_s('a.mkv'));
        t.flushMicrotasks();
        h.engine.emitPosition(const Duration(seconds: 10));
        h.engine.emitPlaying(true);
        t.elapse(const Duration(seconds: 3, milliseconds: 100));

        expect(h.engine.hwdecWrites, ['auto-safe', 'no']);
        expect(h.engine.lastSeek, const Duration(seconds: 10),
            reason: 'a seek in place makes the new decoder show a frame now');
        expect(h.store.forKey('a.mkv')!.decoder, 'sw');
        expect(h.log.entries().single.code, 'KV-504');
        expect(h.c.read(decoderFallbackEventProvider)?.seq, 1);
        h.c.dispose();
      });
    });

    test('the configured wait is honoured', () {
      fakeAsync((t) {
        late _Harness h;
        _harness(tweak: (s) => s.copyWith(decoderStallSeconds: 6))
            .then((v) => h = v);
        t.flushMicrotasks();
        h.ctl.open(_s('a.mkv'));
        t.flushMicrotasks();
        h.engine.emitPlaying(true);
        t.elapse(const Duration(seconds: 5));
        expect(h.engine.hwdecWrites, ['auto-safe']);
        t.elapse(const Duration(seconds: 2));
        expect(h.engine.hwdecWrites, ['auto-safe', 'no']);
        h.c.dispose();
      });
    });

    test('a frame in time means nothing happens', () {
      fakeAsync((t) {
        late _Harness h;
        _harness().then((v) => h = v);
        t.flushMicrotasks();
        h.ctl.open(_s('a.mkv'));
        t.flushMicrotasks();
        h.engine.emitPlaying(true);
        t.elapse(const Duration(seconds: 1));
        h.engine.emitVideoFrame(true);
        t.elapse(const Duration(seconds: 10));
        expect(h.engine.hwdecWrites, ['auto-safe']);
        h.c.dispose();
      });
    });

    test('a file with no video track is not a stall', () {
      fakeAsync((t) {
        late _Harness h;
        _harness().then((v) => h = v);
        t.flushMicrotasks();
        h.engine.hasVideoTrack = false;
        h.ctl.open(_s('a.mkv'));
        t.flushMicrotasks();
        h.engine.emitPlaying(true);
        t.elapse(const Duration(seconds: 10));
        expect(h.engine.hwdecWrites, ['auto-safe']);
        h.c.dispose();
      });
    });

    test('mpv already decoding in software is not switched again', () {
      fakeAsync((t) {
        late _Harness h;
        _harness().then((v) => h = v);
        t.flushMicrotasks();
        h.ctl.open(_s('a.mkv'));
        t.flushMicrotasks();
        h.engine.activeHwdecValue = 'no'; // mpv's own init fallback kicked in
        h.engine.emitPlaying(true);
        t.elapse(const Duration(seconds: 10));
        expect(h.engine.hwdecWrites, ['auto-safe']);
        h.c.dispose();
      });
    });

    test('audio-only mode (video output off) never counts', () {
      fakeAsync((t) {
        late _Harness h;
        _harness().then((v) => h = v);
        t.flushMicrotasks();
        h.engine.videoOutputEnabled = false;
        h.ctl.open(_s('a.mkv'));
        t.flushMicrotasks();
        h.engine.emitPlaying(true);
        t.elapse(const Duration(seconds: 10));
        expect(h.engine.hwdecWrites, ['auto-safe']);
        h.c.dispose();
      });
    });

    test('hardware and software modes do not run the watchdog', () {
      for (final mode in ['hw', 'sw']) {
        fakeAsync((t) {
          late _Harness h;
          _harness(tweak: (s) => s.copyWith(decoderMode: mode))
              .then((v) => h = v);
          t.flushMicrotasks();
          h.ctl.open(_s('a.mkv'));
          t.flushMicrotasks();
          h.engine.emitPlaying(true);
          t.elapse(const Duration(seconds: 10));
          expect(h.engine.hwdecWrites.length, 1, reason: mode);
          h.c.dispose();
        });
      }
    });

    test('opening the next video cancels the previous video\'s clock', () {
      fakeAsync((t) {
        late _Harness h;
        _harness().then((v) => h = v);
        t.flushMicrotasks();
        h.ctl.open(_s('a.mkv'));
        t.flushMicrotasks();
        h.engine.emitPlaying(true);
        t.elapse(const Duration(seconds: 2));
        h.ctl.open(_s('b.mkv'));
        t.flushMicrotasks();
        h.engine.emitVideoFrame(true);
        t.elapse(const Duration(seconds: 10));
        expect(h.store.forKey('a.mkv'), isNull);
        expect(h.store.forKey('b.mkv'), isNull);
        h.c.dispose();
      });
    });
  });

  group('user choices', () {
    test('choosing the default clears the override, anything else stores it',
        () async {
      final h = await _harness();
      addTearDown(h.c.dispose);
      await h.ctl.open(_s('a.mkv'));

      await h.ctl.choose(DecoderMode.software);
      expect(h.store.forKey('a.mkv')!.decoder, 'sw');
      expect(h.engine.hwdecWrites.last, 'no');

      await h.ctl.choose(DecoderMode.auto);
      expect(h.store.forKey('a.mkv'), isNull,
          reason: 'back to the default leaves no record behind');
      expect(h.engine.hwdecWrites.last, 'auto-safe');
    });

    test('undo after a fallback stores explicit hardware, so it cannot loop',
        () async {
      final h = await _harness();
      addTearDown(h.c.dispose);
      var calls = 0;
      h.engine.openHook = (_) {
        if (++calls == 1) throw StateError('mediacodec init');
      };
      await h.ctl.open(_s('a.mkv'));
      expect(h.store.forKey('a.mkv')!.decoder, 'sw');

      await h.ctl.undoFallback();
      expect(h.store.forKey('a.mkv')!.decoder, 'hw');
      expect(h.engine.hwdecWrites.last, 'auto-safe');
    });

    test('the status reflects the effective mode, override and active decoder',
        () async {
      final h = await _harness();
      addTearDown(h.c.dispose);
      await h.ctl.open(_s('a.mkv'));
      await h.ctl.refreshStatus();
      var s = h.c.read(decoderStatusProvider)!;
      expect(s.mode, DecoderMode.auto);
      expect(s.overridden, isFalse);
      expect(s.active, 'mediacodec-copy');

      await h.ctl.choose(DecoderMode.software);
      s = h.c.read(decoderStatusProvider)!;
      expect(s.mode, DecoderMode.software);
      expect(s.overridden, isTrue);
      expect(s.active, 'no');
    });

    test('forgetAll clears every override but keeps the other prefs', () async {
      final h = await _harness();
      addTearDown(h.c.dispose);
      await h.store.put('a.mkv', const VideoTrackPrefs(decoder: 'sw'));
      await h.store.put(
          'b.mkv', const VideoTrackPrefs(decoder: 'hw', subtitleDelayMs: 300));
      await h.store.put('c.mkv', const VideoTrackPrefs(audioDelayMs: 50));

      expect(await h.ctl.forgetAll(), 2);
      expect(h.store.forKey('a.mkv'), isNull);
      expect(h.store.forKey('b.mkv')!.decoder, isNull);
      expect(h.store.forKey('b.mkv')!.subtitleDelayMs, 300);
      expect(h.store.forKey('c.mkv')!.audioDelayMs, 50);
    });
  });
}
