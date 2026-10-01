import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_log_provider.dart';
import '../../core/errors/kivo_failure.dart';
import '../../platform/cast_platform_provider.dart';
import '../open/video_source.dart';
import 'dlna_network.dart';
import 'upnp.dart';

enum CastPhase { idle, connecting, casting }

/// Why a cast ended other than by the player's "Dejar de enviar": the film
/// finished on the TV, the TV stopped answering, or the notification's stop.
enum CastEnd { finished, lost, stopped }

class CastState {
  final CastPhase phase;
  final DlnaRenderer? device;

  /// The video on the TV ([VideoSession.resumeKey]); the player shows the
  /// cast screen only for this one.
  final String? resumeKey;
  final Duration position;
  final Duration duration;
  final bool playing;

  const CastState({
    this.phase = CastPhase.idle,
    this.device,
    this.resumeKey,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
  });

  static const idle = CastState();

  bool get active => phase != CastPhase.idle;

  /// Casting [key]'s video (connecting included).
  bool isCasting(String? key) => active && key != null && resumeKey == key;

  CastState copyWith({
    CastPhase? phase,
    Duration? position,
    Duration? duration,
    bool? playing,
  }) =>
      CastState(
        phase: phase ?? this.phase,
        device: device,
        resumeKey: resumeKey,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        playing: playing ?? this.playing,
      );
}

/// Finds TVs. Real SSDP by default; tests override it.
final tvDiscoveryProvider = Provider<TvDiscovery>((ref) => SsdpTvDiscovery());

/// One [TvTransport] per renderer. Real SOAP by default; tests override it.
final tvTransportFactoryProvider =
    Provider<TvTransport Function(DlnaRenderer)>((ref) =>
        (r) => SoapTvTransport(r.avTransportControl));

/// The phone's addresses, for the URL the TV fetches. Tests override it.
final localAddressesProvider =
    Provider<Future<List<String>> Function()>((ref) => localIpv4s);

/// Set when a cast ends other than by the player's own stop, with where the
/// TV was, so the player can carry on from there (and say why).
final castEndedProvider = StateProvider<(CastEnd, Duration)?>((ref) => null);

final castControllerProvider =
    NotifierProvider<CastController, CastState>(CastController.new);

/// "Enviar a la TV": serves the video, hands its URL to the TV over UPnP,
/// then mirrors the TV's position and play state once a second.
///
/// Every start bumps a generation; anything awaited on behalf of an older
/// one (a start the user stopped half-way, a poll in flight at stop) finds
/// the generation moved on and does nothing.
class CastController extends Notifier<CastState> {
  TvTransport? _tv;
  Timer? _poll;
  bool _polling = false;
  int _pollFailures = 0;
  bool _sawPlaying = false;
  int _gen = 0;
  StreamSubscription<void>? _stopSub;

  @override
  CastState build() {
    ref.onDispose(() {
      _poll?.cancel();
      _stopSub?.cancel();
      _tv?.close();
    });
    // Another video opened anywhere (player, library, mini-player, a
    // shortcut) ends the cast of this one — not only while a player is up.
    ref.listen<VideoSession?>(currentVideoProvider, (_, next) {
      if (state.active && next?.resumeKey != state.resumeKey) stop();
    });
    return CastState.idle;
  }

  /// Sends [source] to [device], starting at [startAt]. Throws a
  /// [KivoFailure] (KV-505, logged) if the TV will not take it.
  Future<void> start(
    DlnaRenderer device, {
    required String source,
    required String title,
    required String resumeKey,
    Duration startAt = Duration.zero,
    Duration? duration,
  }) async {
    if (state.active) await stop();
    final gen = ++_gen;
    bool stale() => gen != _gen;
    final platform = ref.read(castPlatformProvider);
    ref.read(castEndedProvider.notifier).state = null;
    state = CastState(
      phase: CastPhase.connecting,
      device: device,
      resumeKey: resumeKey,
      position: startAt,
      duration: duration ?? Duration.zero,
    );
    try {
      // First, while the app is certainly in the foreground: Android 12+
      // refuses to start a foreground service from the background, and the
      // connect below can take long enough for the screen to go off.
      await platform.keepAlive(true, device: device.name);
      _stopSub ??= platform.stopRequests.listen((_) => _stopFromNotification());
      final served = await platform.serve(source);
      if (stale()) return;
      final ips = await ref.read(localAddressesProvider)();
      if (stale()) return;
      final host = pickLocalAddress(ips, device.host);
      if (host == null) throw StateError('no local IPv4 for ${device.host}');
      final url = 'http://$host:${served.port}${served.path}';
      final tv = ref.read(tvTransportFactoryProvider)(device);
      _tv = tv;
      await tv.setUri(
        url,
        didlLite(
          title: title,
          url: url,
          mime: served.mime,
          size: served.size,
          duration: duration,
        ),
      );
      if (stale()) return;
      await tv.play();
      if (stale()) return;
      if (startAt > const Duration(seconds: 3)) {
        await _seekOnceReady(tv, startAt, stale);
        if (stale()) return;
      }
      _sawPlaying = false;
      _pollFailures = 0;
      state = state.copyWith(phase: CastPhase.casting, playing: true);
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh(gen));
    } catch (e) {
      if (stale()) return; // stopped meanwhile: not a failure
      await _teardown(sendStop: false);
      final failure = KivoFailure(KivoOp.cast, e);
      ref.read(errorLogProvider).record(failure);
      throw failure;
    }
  }

  /// Many TVs refuse a Seek until playback has actually started.
  Future<void> _seekOnceReady(
      TvTransport tv, Duration to, bool Function() stale) async {
    for (var i = 0; i < 20 && !stale(); i++) {
      final s = await tv.state().catchError((_) => TvState.unknown);
      if (s == TvState.playing || s == TvState.paused) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (stale()) return;
    try {
      await tv.seek(to);
    } catch (_) {
      // Starting from the beginning beats not starting at all.
    }
  }

  Future<void> _refresh(int gen) async {
    final tv = _tv;
    // One poll at a time: a slow TV must not pile up requests (and then be
    // declared lost for answering late).
    if (tv == null || _polling || gen != _gen || state.phase != CastPhase.casting) {
      return;
    }
    _polling = true;
    try {
      final (pos, dur) = await tv.position();
      final s = await tv.state();
      if (gen != _gen || state.phase != CastPhase.casting) return;
      _pollFailures = 0;
      if (s == TvState.playing) _sawPlaying = true;
      state = state.copyWith(
        position: pos ?? state.position,
        duration: (dur != null && dur > Duration.zero) ? dur : state.duration,
        playing: s == TvState.playing ||
            (s == TvState.transitioning && state.playing),
      );
      // Stopped after it had been playing: the film ended on the TV, or
      // someone stopped it with the TV's remote.
      if (s == TvState.stopped && _sawPlaying) {
        await _endBy(CastEnd.finished);
      }
    } catch (e) {
      if (gen != _gen || state.phase != CastPhase.casting) return;
      // A dropped reply now and then is Wi-Fi; five in a row is a TV gone.
      if (++_pollFailures >= 5) {
        ref.read(errorLogProvider).record(KivoFailure(KivoOp.cast, e));
        await _endBy(CastEnd.lost);
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _endBy(CastEnd why) async {
    final at = state.position;
    await _teardown(sendStop: why == CastEnd.stopped);
    ref.read(castEndedProvider.notifier).state = (why, at);
  }

  Future<void> _stopFromNotification() async {
    if (state.active) await _endBy(CastEnd.stopped);
  }

  Future<void> togglePlay() => state.playing ? pause() : play();

  Future<void> play() => _setPlaying(true);
  Future<void> pause() => _setPlaying(false);

  Future<void> _setPlaying(bool play) async {
    final tv = _tv;
    if (tv == null || state.phase != CastPhase.casting) return;
    final was = state.playing;
    state = state.copyWith(playing: play); // answer the tap now
    try {
      play ? await tv.play() : await tv.pause();
    } catch (_) {
      if (state.phase == CastPhase.casting) state = state.copyWith(playing: was);
    }
  }

  Future<void> seekTo(Duration to) async {
    final tv = _tv;
    if (tv == null || state.phase != CastPhase.casting) return;
    final max = state.duration > Duration.zero ? state.duration : to;
    final target = to < Duration.zero ? Duration.zero : (to > max ? max : to);
    state = state.copyWith(position: target);
    try {
      await tv.seek(target);
    } catch (_) {}
  }

  Future<void> skip(int seconds) => seekTo(state.position + Duration(seconds: seconds));

  /// Ends the cast ("Dejar de enviar"), also half-way through connecting.
  /// Returns where the TV was, so the phone can carry on from there.
  Future<Duration> stop() async {
    final at = state.position;
    await _teardown(sendStop: true);
    return at;
  }

  Future<void> _teardown({required bool sendStop}) async {
    _gen++; // anything in flight for the old cast is now stale
    _poll?.cancel();
    _poll = null;
    final tv = _tv;
    _tv = null;
    state = CastState.idle;
    final platform = ref.read(castPlatformProvider);
    if (tv != null) {
      if (sendStop) {
        try {
          await tv.stop();
        } catch (_) {}
      }
      tv.close();
    }
    try {
      await platform.stopServing();
    } catch (_) {}
    try {
      await platform.keepAlive(false);
    } catch (_) {}
  }
}
