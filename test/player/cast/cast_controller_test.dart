import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log_provider.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/platform/cast_platform_provider.dart';
import 'package:kivo_player/platform/interfaces/cast_platform.dart';
import 'package:kivo_player/player/cast/cast_controller.dart';
import 'package:kivo_player/player/cast/dlna_network.dart';
import 'package:kivo_player/player/cast/upnp.dart';
import 'package:kivo_player/player/open/video_source.dart';

class FakeCastPlatform implements CastPlatform {
  final served = <String>[];
  int stops = 0;
  final keepAlives = <bool>[];
  final stopCtrl = StreamController<void>.broadcast();

  @override
  Future<void> multicastLock(bool on) async {}
  @override
  Future<ServedVideo> serve(String source) async {
    served.add(source);
    return const ServedVideo(
      port: 4000,
      path: '/v/tok.mkv',
      mime: 'video/x-matroska',
      size: 99,
    );
  }

  @override
  Future<void> stopServing() async => stops++;
  @override
  Future<void> keepAlive(bool on, {String device = ''}) async =>
      keepAlives.add(on);
  @override
  Stream<void> get stopRequests => stopCtrl.stream;
}

class FakeTv implements TvTransport {
  final calls = <String>[];
  bool closed = false;

  @override
  void close() => closed = true;
  String? uri;
  String? metadata;
  TvState now = TvState.playing;
  Duration pos = Duration.zero;
  Duration? dur = const Duration(minutes: 10);
  bool refuse = false;
  bool unreachable = false;

  void _check(String c) {
    if (unreachable) throw UpnpCallException(c, 'timeout');
    calls.add(c);
  }

  @override
  Future<void> setUri(String url, String meta) async {
    if (refuse) throw UpnpCallException('SetAVTransportURI', 'UPnP 714');
    _check('setUri');
    uri = url;
    metadata = meta;
  }

  @override
  Future<void> play() async => _check('play');
  @override
  Future<void> pause() async => _check('pause');
  @override
  Future<void> stop() async => _check('stop');
  @override
  Future<void> seek(Duration to) async {
    _check('seek ${formatUpnpTime(to)}');
    pos = to;
  }

  @override
  Future<(Duration?, Duration?)> position() async {
    _check('position');
    return (pos, dur);
  }

  @override
  Future<TvState> state() async {
    _check('state');
    return now;
  }
}

final _tv1 = DlnaRenderer(
  id: 'uuid:1',
  name: 'Salón',
  avTransportControl: Uri.parse('http://192.168.1.20:9197/avt'),
);

void main() {
  late FakeCastPlatform platform;
  late FakeTv tv;
  late ProviderContainer c;

  setUp(() {
    platform = FakeCastPlatform();
    tv = FakeTv();
    c = ProviderContainer(
      overrides: [
        castPlatformProvider.overrideWithValue(platform),
        tvTransportFactoryProvider.overrideWithValue((_) => tv),
        localAddressesProvider.overrideWithValue(
          () async => ['10.1.1.1', '192.168.1.33'],
        ),
      ],
    );
  });
  tearDown(() => c.dispose());

  Future<void> start({Duration at = Duration.zero}) => c
      .read(castControllerProvider.notifier)
      .start(
        _tv1,
        source: 'content://media/external/video/media/7',
        title: 'Película.mkv',
        resumeKey: 'Película.mkv',
        startAt: at,
        duration: const Duration(minutes: 10),
      );

  test(
    'serves the video, gives the TV a URL on its subnet, and plays it',
    () async {
      await start();
      expect(platform.served, ['content://media/external/video/media/7']);
      expect(tv.uri, 'http://192.168.1.33:4000/v/tok.mkv');
      expect(tv.metadata, contains('<dc:title>Película.mkv</dc:title>'));
      expect(tv.calls.take(2), ['setUri', 'play']);
      expect(platform.keepAlives, [true]);
      final s = c.read(castControllerProvider);
      expect(s.phase, CastPhase.casting);
      expect(s.resumeKey, 'Película.mkv');
      expect(s.device, _tv1);
      await c.read(castControllerProvider.notifier).stop();
    },
  );

  test('picks up where the phone was, once the TV is playing', () async {
    await start(at: const Duration(minutes: 3, seconds: 5));
    expect(tv.calls, contains('seek 0:03:05'));
    await c.read(castControllerProvider.notifier).stop();
  });

  test(
    'a TV that refuses the video is KV-505, logged, and nothing is left running',
    () async {
      tv.refuse = true;
      await expectLater(
        start(),
        throwsA(isA<KivoFailure>().having((f) => f.code, 'code', 'KV-505')),
      );
      expect(c.read(castControllerProvider).phase, CastPhase.idle);
      expect(platform.stops, 1);
      expect(c.read(errorLogProvider).entries().single.code, 'KV-505');
    },
  );

  test(
    '"Dejar de enviar" stops the TV and the server, and says where it was',
    () async {
      await start();
      tv.pos = const Duration(minutes: 4);
      await c
          .read(castControllerProvider.notifier)
          .seekTo(const Duration(minutes: 4));
      final at = await c.read(castControllerProvider.notifier).stop();
      expect(at, const Duration(minutes: 4));
      expect(tv.calls.last, 'stop');
      expect(platform.stops, 1);
      expect(platform.keepAlives, [true, false]);
      expect(c.read(castControllerProvider).active, false);
    },
  );

  test('the notification\'s stop ends the cast', () async {
    await start();
    platform.stopCtrl.add(null);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(castControllerProvider).active, false);
  });

  test('play/pause and skips go to the TV, clamped to the video', () async {
    await start();
    final ctrl = c.read(castControllerProvider.notifier);
    await ctrl.togglePlay();
    expect(tv.calls.last, 'pause');
    expect(c.read(castControllerProvider).playing, false);
    await ctrl.skip(-30);
    expect(tv.calls.last, 'seek 0:00:00');
    await ctrl.seekTo(const Duration(hours: 2));
    expect(tv.calls.last, 'seek 0:10:00');
    await ctrl.stop();
  });

  // testWidgets for its fake clock: the poll is a 1 s timer.
  testWidgets('mirrors the TV, and a film that ends there ends the cast', (
    t,
  ) async {
    {
      await start();
      tv.pos = const Duration(minutes: 2);
      await t.pump(const Duration(seconds: 1));
      expect(
        c.read(castControllerProvider).position,
        const Duration(minutes: 2),
      );
      tv.now = TvState.stopped;
      await t.pump(const Duration(seconds: 1));
      expect(c.read(castControllerProvider).active, false);
      expect(c.read(castEndedProvider)?.$1, CastEnd.finished);
    }
  });

  testWidgets('five unanswered polls in a row: the TV is gone', (t) async {
    await start();
    tv.pos = const Duration(minutes: 1);
    await t.pump(const Duration(seconds: 1));
    tv.unreachable = true;
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(
      c.read(castControllerProvider).active,
      true,
      reason: 'Wi-Fi hiccups happen',
    );
    await t.pump(const Duration(seconds: 1));
    expect(c.read(castControllerProvider).active, false);
    expect(c.read(castEndedProvider), (
      CastEnd.lost,
      const Duration(minutes: 1),
    ));
  });

  test('a stop half-way through connecting leaves nothing behind', () async {
    final gate = Completer<void>();
    final slow = _SlowTv(gate);
    final c2 = ProviderContainer(
      overrides: [
        castPlatformProvider.overrideWithValue(platform),
        tvTransportFactoryProvider.overrideWithValue((_) => slow),
        localAddressesProvider.overrideWithValue(() async => ['192.168.1.33']),
      ],
    );
    addTearDown(c2.dispose);
    final starting = c2
        .read(castControllerProvider.notifier)
        .start(_tv1, source: 's', title: 't', resumeKey: 'k');
    await Future<void>.delayed(Duration.zero);
    expect(c2.read(castControllerProvider).phase, CastPhase.connecting);
    await c2.read(castControllerProvider.notifier).stop();
    gate.complete();
    await starting; // finishes quietly: not a failure
    expect(c2.read(castControllerProvider).active, false);
    expect(platform.keepAlives.last, false);
    expect(slow.calls, isNot(contains('play')));
  });

  test('another video opened anywhere ends the cast', () async {
    await start();
    c
        .read(currentVideoProvider.notifier)
        .open(
          const VideoSession(
            playbackPath: '/other.mkv',
            displayName: 'other.mkv',
            queue: ['/other.mkv'],
            index: 0,
          ),
        );
    await Future<void>.delayed(Duration.zero);
    expect(c.read(castControllerProvider).active, false);
    expect(tv.closed, true);
  });

  test('the notification stop says where the TV was', () async {
    await start();
    await c
        .read(castControllerProvider.notifier)
        .seekTo(const Duration(minutes: 2));
    platform.stopCtrl.add(null);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(castEndedProvider), (
      CastEnd.stopped,
      const Duration(minutes: 2),
    ));
  });

  test('pause on a paused TV stays paused', () async {
    await start();
    final ctrl = c.read(castControllerProvider.notifier);
    await ctrl.pause();
    await ctrl.pause();
    expect(tv.calls.where((x) => x == 'pause').length, 2);
    expect(tv.calls.last, 'pause');
    expect(c.read(castControllerProvider).playing, false);
    await ctrl.stop();
  });
}

class _SlowTv extends FakeTv {
  final Completer<void> gate;
  _SlowTv(this.gate);
  @override
  Future<void> setUri(String url, String meta) async {
    await gate.future;
    await super.setUri(url, meta);
  }
}
