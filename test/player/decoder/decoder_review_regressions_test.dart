import 'dart:async';
import 'package:kivo_player/player/engine/video_progress.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/errors/error_log_provider.dart';
import 'package:kivo_player/core/settings/kivo_settings.dart';
import 'package:kivo_player/core/settings/settings_provider.dart';
import 'package:kivo_player/core/settings/settings_service.dart';
import 'package:kivo_player/player/decoder/decoder_controller.dart';
import 'package:kivo_player/player/engine/playback_provider.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/player/tracks/track_prefs_store.dart';

import '../../fakes/fakes.dart';

VideoSession _s(String name) => VideoSession(
  playbackPath: '/v/$name',
  displayName: name,
  queue: ['/v/$name'],
  index: 0,
);

class _H {
  _H(this.c, this.engine, this.store);
  final ProviderContainer c;
  final FakePlaybackEngine engine;
  final InMemoryTrackPrefsStore store;
  DecoderController get ctl => c.read(decoderControllerProvider);
}

Future<_H> _harness({
  KivoSettings Function(KivoSettings)? tweak,
  FakePlaybackEngine? suppliedEngine,
}) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  if (tweak != null) await svc.update(tweak(svc.current));
  final engine = suppliedEngine ?? FakePlaybackEngine();
  final store = InMemoryTrackPrefsStore();
  final c = ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(svc),
      playbackEngineProvider.overrideWithValue(engine),
      trackPrefsStoreProvider.overrideWithValue(store),
      errorLogProvider.overrideWithValue(
        ErrorLog(InMemoryErrorLogStore(), appVersion: 't', androidSdk: 0),
      ),
    ],
  );
  return _H(c, engine, store);
}

_H _inFake(FakeAsync t, [KivoSettings Function(KivoSettings)? tweak]) {
  late _H h;
  _harness(tweak: tweak).then((v) => h = v);
  t.flushMicrotasks();
  return h;
}

class _LoadingEngine extends FakePlaybackEngine {
  final loaded = Completer<void>();
  @override
  Future<void> open(
    String path, {
    Duration startAt = Duration.zero,
    bool play = true,
  }) async {
    await loaded.future;
    await super.open(path, startAt: startAt, play: play);
  }
}

void main() {
  test(
    'old frame/clock readings while a new file loads cannot change its decoder',
    () {
      fakeAsync((t) {
        final engine = _LoadingEngine();
        late _H h;
        _harness(suppliedEngine: engine).then((value) => h = value);
        t.flushMicrotasks();
        h.ctl.open(_s('new-file.mkv'));
        t.flushMicrotasks();
        engine.videoSizeValue = (width: 720, height: 404);
        engine.emitPlaying(true);
        engine.emitVideoFrame(true);
        for (var second = 0; second < 6; second++) {
          engine.emitVideoProgress(
            VideoProgress(
              position: Duration(seconds: 10 + second),
              videoPosition: const Duration(seconds: 10),
              sampledAt: Duration(seconds: second),
            ),
          );
          t.elapse(const Duration(seconds: 1));
        }
        expect(engine.hwdecWrites, [
          'auto-safe',
        ], reason: 'load has not completed');
        engine.loaded.complete();
        t.flushMicrotasks();
        expect(h.store.forKey(_s('new-file.mkv').resumeKey), isNull);
        h.c.dispose();
      });
    },
  );

  test('frozen Aida picture with advancing audio recovers after first frame', () {
    fakeAsync((t) {
      final h = _inFake(t);
      h.ctl.open(_s('Aida 11x36.avi'));
      t.flushMicrotasks();
      h.engine.videoSizeValue = (width: 720, height: 404);
      h.engine.emitPlaying(true);
      h.engine.emitVideoFrame(true);
      t.flushMicrotasks();
      for (var second = 0; second <= 5; second++) {
        h.engine.emitPosition(Duration(seconds: 10 + second));
        h.engine.emitVideoProgress(
          VideoProgress(
            position: Duration(seconds: 10 + second),
            videoPosition: const Duration(seconds: 10),
            sampledAt: Duration(seconds: second),
          ),
        );
        t.elapse(const Duration(seconds: 1));
      }
      expect(
        h.engine.hwdecWrites,
        ['auto-safe', 'no'],
        reason:
            'known dimensions and one earlier frame do not prove video is still moving',
      );
      expect(h.store.forKey(_s('Aida 11x36.avi').resumeKey)?.decoder, 'sw');
      expect(h.engine.seekCount, 1, reason: 'one recovery, not a loop');
      h.c.dispose();
    });
  });

  test('slow advancing 4K video keeps hardware instead of falling back', () {
    fakeAsync((t) {
      final h = _inFake(t);
      h.ctl.open(_s('slow-4k.mkv'));
      t.flushMicrotasks();
      h.engine.videoSizeValue = (width: 3840, height: 2160);
      h.engine.emitPlaying(true);
      h.engine.emitVideoFrame(true);
      for (var second = 0; second < 20; second++) {
        h.engine.emitVideoProgress(
          VideoProgress(
            position: Duration(seconds: second),
            videoPosition: Duration(milliseconds: second * 100),
            sampledAt: Duration(seconds: second),
          ),
        );
        t.elapse(const Duration(seconds: 1));
      }
      expect(h.engine.hwdecWrites, ['auto-safe']);
      expect(h.engine.seekCount, 0);
      h.c.dispose();
    });
  });

  for (final mode in [
    'hw',
    'sw',
    'fallback-off',
    'paused',
    'seeking',
    'output-off',
    'already-software',
  ]) {
    test('frozen-picture recovery respects $mode', () {
      fakeAsync((t) {
        final h = _inFake(
          t,
          (s) => s.copyWith(
            decoderMode: mode == 'hw' || mode == 'sw' ? mode : 'auto',
            decoderAutoFallback: mode != 'fallback-off',
          ),
        );
        h.ctl.open(_s('a.avi'));
        t.flushMicrotasks();
        h.engine.videoSizeValue = (width: 720, height: 404);
        h.engine.emitPlaying(true);
        h.engine.emitVideoFrame(true);
        if (mode == 'output-off') h.engine.videoOutputEnabled = false;
        if (mode == 'already-software') h.engine.activeHwdecValue = 'no';
        for (var second = 0; second < 10; second++) {
          h.engine.emitVideoProgress(
            VideoProgress(
              position: Duration(seconds: second),
              videoPosition: Duration.zero,
              sampledAt: Duration(seconds: second),
              paused: mode == 'paused',
              seeking: mode == 'seeking',
            ),
          );
          t.elapse(const Duration(seconds: 1));
        }
        expect(h.engine.hwdecWrites, [mode == 'sw' ? 'no' : 'auto-safe']);
        expect(h.engine.seekCount, 0);
        expect(h.store.forKey(_s('a.avi').resumeKey), isNull);
        h.c.dispose();
      });
    });
  }

  // media_kit reports buffering=true (mpv core-idle) until the first frame —
  // which, with a dead hardware decoder, is forever.
  test(
    'buffering reported until the first frame does not silence the watchdog',
    () {
      fakeAsync((t) {
        final h = _inFake(t);
        h.ctl.open(_s('a.mkv'));
        t.flushMicrotasks();
        h.engine.emitBuffering(true);
        h.engine.emitPlaying(true);
        t.elapse(const Duration(seconds: 4));
        expect(h.engine.hwdecWrites, ['auto-safe', 'no']);
        h.c.dispose();
      });
    },
  );

  test(
    'opened while the output is off, it counts once the output comes back',
    () {
      fakeAsync((t) {
        final h = _inFake(t);
        h.engine.videoOutputEnabled = false; // autoplay while minimized
        h.ctl.open(_s('a.mkv'));
        t.flushMicrotasks();
        h.engine.emitPlaying(true);
        t.elapse(const Duration(seconds: 10));
        expect(h.engine.hwdecWrites, ['auto-safe']);

        h.engine.setVideoTrackEnabled(true); // back in the foreground
        t.flushMicrotasks();
        t.elapse(const Duration(seconds: 4));
        expect(h.engine.hwdecWrites, ['auto-safe', 'no']);
        h.c.dispose();
      });
    },
  );

  test('the output going off just as the clock runs out keeps watching', () {
    fakeAsync((t) {
      final h = _inFake(t);
      h.ctl.open(_s('a.mkv'));
      t.flushMicrotasks();
      h.engine.emitPlaying(true);
      t.elapse(const Duration(milliseconds: 2900));
      // Home pressed: the output flag flips with no event reaching us yet.
      h.engine.videoOutputEnabled = false;
      t.elapse(const Duration(milliseconds: 200));
      expect(h.engine.hwdecWrites, ['auto-safe'], reason: 'not a verdict');

      h.engine.setVideoTrackEnabled(true);
      t.flushMicrotasks();
      t.elapse(const Duration(seconds: 4));
      expect(
        h.engine.hwdecWrites,
        ['auto-safe', 'no'],
        reason: 're-armed, so the dead decoder is still caught',
      );
      h.c.dispose();
    });
  });

  test('a stall switch seeks back to the resume point, not to zero', () {
    fakeAsync((t) {
      final h = _inFake(t);
      h.ctl.open(_s('a.mkv'), startAt: const Duration(minutes: 40));
      t.flushMicrotasks();
      h.engine.emitPlaying(true);
      t.elapse(const Duration(seconds: 4));
      expect(h.engine.lastSeek, const Duration(minutes: 40));
      h.c.dispose();
    });
  });

  test('undo does nothing once another video is on screen', () async {
    final h = await _harness();
    addTearDown(h.c.dispose);
    var calls = 0;
    h.engine.openHook = (_) {
      if (++calls == 1) throw StateError('mediacodec init');
    };
    await h.ctl.open(_s('a.mkv'));
    await h.ctl.open(_s('b.mkv'));

    await h.ctl.undoFallback('a.mkv');
    expect(h.store.forKey(_s('b.mkv').resumeKey), isNull);
    expect(h.store.forKey(_s('a.mkv').resumeKey)!.decoder, 'sw');
    expect(h.engine.hwdecWrites.last, 'auto-safe', reason: "b's own open");
  });

  test('a failing open superseded by the next one does not retry', () async {
    final h = await _harness();
    addTearDown(h.c.dispose);
    h.engine.openHook = (path) {
      if (path == '/v/a.mkv') throw StateError('mediacodec init');
    };
    // Started back to back: b begins while a is still on its first await, so
    // a's failure arrives after b has taken over.
    final a = h.ctl.open(_s('a.mkv'));
    final b = h.ctl.open(_s('b.mkv'));
    await a;
    await b;
    expect(h.engine.openedPath, '/v/b.mkv');
    expect(
      h.store.forKey(_s('a.mkv').resumeKey),
      isNull,
      reason: 'no fallback recorded',
    );
    expect(h.engine.hwdecWrites.where((v) => v == 'no'), isEmpty);
  });

  test(
    'falling back with a software default stores no redundant override',
    () async {
      final h = await _harness(tweak: (s) => s.copyWith(decoderMode: 'sw'));
      addTearDown(h.c.dispose);
      await h.store.put(
        _s('a.mkv').resumeKey,
        const VideoTrackPrefs(decoder: 'auto'),
      );
      var calls = 0;
      h.engine.openHook = (_) {
        if (++calls == 1) throw StateError('mediacodec init');
      };
      await h.ctl.open(_s('a.mkv'));
      expect(
        h.store.forKey(_s('a.mkv').resumeKey),
        isNull,
        reason: 'software is already the default',
      );
    },
  );
}
