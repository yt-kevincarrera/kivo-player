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
    playbackPath: '/v/$name', displayName: name, queue: ['/v/$name'], index: 0);

class _H {
  _H(this.c, this.engine, this.store);
  final ProviderContainer c;
  final FakePlaybackEngine engine;
  final InMemoryTrackPrefsStore store;
  DecoderController get ctl => c.read(decoderControllerProvider);
}

Future<_H> _harness({KivoSettings Function(KivoSettings)? tweak}) async {
  final svc = await SettingsService.load(InMemorySettingsStore());
  if (tweak != null) await svc.update(tweak(svc.current));
  final engine = FakePlaybackEngine();
  final store = InMemoryTrackPrefsStore();
  final c = ProviderContainer(overrides: [
    settingsServiceProvider.overrideWithValue(svc),
    playbackEngineProvider.overrideWithValue(engine),
    trackPrefsStoreProvider.overrideWithValue(store),
    errorLogProvider.overrideWithValue(
        ErrorLog(InMemoryErrorLogStore(), appVersion: 't', androidSdk: 0)),
  ]);
  return _H(c, engine, store);
}

_H _inFake(FakeAsync t, [KivoSettings Function(KivoSettings)? tweak]) {
  late _H h;
  _harness(tweak: tweak).then((v) => h = v);
  t.flushMicrotasks();
  return h;
}

void main() {
  // media_kit reports buffering=true (mpv core-idle) until the first frame —
  // which, with a dead hardware decoder, is forever.
  test('buffering reported until the first frame does not silence the watchdog',
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
  });

  test('opened while the output is off, it counts once the output comes back',
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
  });

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
      expect(h.engine.hwdecWrites, ['auto-safe', 'no'],
          reason: 're-armed, so the dead decoder is still caught');
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
    expect(h.store.forKey('b.mkv'), isNull);
    expect(h.store.forKey('a.mkv')!.decoder, 'sw');
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
    expect(h.store.forKey('a.mkv'), isNull, reason: 'no fallback recorded');
    expect(h.engine.hwdecWrites.where((v) => v == 'no'), isEmpty);
  });

  test('falling back with a software default stores no redundant override',
      () async {
    final h = await _harness(tweak: (s) => s.copyWith(decoderMode: 'sw'));
    addTearDown(h.c.dispose);
    await h.store.put('a.mkv', const VideoTrackPrefs(decoder: 'auto'));
    var calls = 0;
    h.engine.openHook = (_) {
      if (++calls == 1) throw StateError('mediacodec init');
    };
    await h.ctl.open(_s('a.mkv'));
    expect(h.store.forKey('a.mkv'), isNull,
        reason: 'software is already the default');
  });
}
