import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_log_provider.dart';
import '../../core/errors/kivo_failure.dart';
import '../../core/settings/settings_provider.dart';
import '../engine/playback_engine.dart';
import '../engine/playback_provider.dart';
import '../open/guarded_open.dart';
import '../open/video_source.dart';
import '../tracks/track_prefs_store.dart';
import 'decoder_mode.dart';
import 'decoder_stall_watchdog.dart';

/// What the player's decoder row shows.
@immutable
class DecoderStatus {
  const DecoderStatus({
    required this.mode,
    required this.overridden,
    required this.active,
  });

  /// The effective mode for the current video.
  final DecoderMode mode;

  /// Whether that mode is this video's own (differs from the default).
  final bool overridden;

  /// mpv's `hwdec-current`, or null while nothing is decoding.
  final String? active;

  @override
  bool operator ==(Object other) =>
      other is DecoderStatus &&
      other.mode == mode &&
      other.overridden == overridden &&
      other.active == active;

  @override
  int get hashCode => Object.hash(mode, overridden, active);
}

/// One automatic switch to software, for the player screen's "Deshacer" toast.
/// [seq] makes two fallbacks on the same video distinct events.
@immutable
class DecoderFallbackEvent {
  const DecoderFallbackEvent(this.resumeKey, this.seq);
  final String resumeKey;
  final int seq;

  @override
  bool operator ==(Object other) =>
      other is DecoderFallbackEvent &&
      other.resumeKey == resumeKey &&
      other.seq == seq;

  @override
  int get hashCode => Object.hash(resumeKey, seq);
}

final decoderStatusProvider = StateProvider<DecoderStatus?>((ref) => null);

final decoderFallbackEventProvider =
    StateProvider<DecoderFallbackEvent?>((ref) => null);

/// Owns which decoder each video plays with: writes `hwdec` on every open,
/// runs the stall watchdog in automatic mode, and switches to software (and
/// remembers it) when the hardware decoder fails.
///
/// App-scoped, like the autoplay coordinator: both the player screen and the
/// minimized autoplay path open videos through [open], so the policy holds no
/// matter which of them started playback.
class DecoderController {
  DecoderController(this._ref) {
    _watchdog = DecoderStallWatchdog(onStall: _onStall);
  }

  final Ref _ref;
  late final DecoderStallWatchdog _watchdog;
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _listening = false;
  Duration _lastPosition = Duration.zero;

  /// The video [open] last set up. Also guards async work against a newer
  /// open having happened in the meantime.
  VideoSession? _session;
  int _openSeq = 0;
  int _fallbackSeq = 0;

  PlaybackEngine get _engine => _ref.read(playbackEngineProvider);
  TrackPrefsStore get _prefs => _ref.read(trackPrefsStoreProvider);

  void _ensureListening() {
    if (_listening) return;
    _listening = true;
    final e = _engine;
    _subs.add(e.positionStream.listen((p) => _lastPosition = p));
    _subs.add(e.playingStream.listen((v) =>
        _watchdog.update(playing: v, outputEnabled: e.videoOutputEnabled)));
    _subs.add(e.bufferingStream.listen((v) =>
        _watchdog.update(buffering: v, outputEnabled: e.videoOutputEnabled)));
    _subs.add(e.hasVideoFrameStream.listen((v) =>
        _watchdog.update(frame: v, outputEnabled: e.videoOutputEnabled)));
  }

  DecoderMode _modeFor(String resumeKey) => resolveDecoderMode(
        global: _ref.read(settingsProvider).decoderMode,
        perVideo: _prefs.forKey(resumeKey)?.decoder,
      );

  /// Opens [session] with its decoder. Throws the same [KivoFailure]
  /// (KV-501) as [guardedOpen] when the file cannot be opened at all.
  Future<void> open(VideoSession session, {Duration startAt = Duration.zero}) async {
    _ensureListening();
    _watchdog.disarm();
    _session = session;
    final seq = ++_openSeq;
    final settings = _ref.read(settingsProvider);
    final mode = _modeFor(session.resumeKey);
    final fallbackAllowed = mode.watched && settings.decoderAutoFallback;
    final engine = _engine;
    final log = _ref.read(errorLogProvider);

    // Unconditional: hwdec is a global mpv option on the process-lifetime
    // player and survives loadfile — skipping this when "the mode didn't
    // change" is how the previous video's software mode would leak into this
    // one.
    await _setHwdec(mode.mpvHwdec);

    if (fallbackAllowed) {
      try {
        await engine.open(session.playbackPath, startAt: startAt);
      } catch (e) {
        // Hardware could not even open it. One retry in software before this
        // becomes a KV-501; the retry is the one that gets logged if it fails.
        await _setHwdec(DecoderMode.software.mpvHwdec);
        await guardedOpen(engine, session.playbackPath, log, startAt: startAt);
        if (seq != _openSeq) return;
        await _fallBack(session, 'open failed with hwdec=${mode.mpvHwdec}: $e');
        return;
      }
      if (seq != _openSeq) return;
      _watchdog.arm(
        Duration(seconds: settings.decoderStallSeconds.clamp(1, 10)),
        frameAlreadyShown: engine.videoSize != null,
      );
      // The watchdog only hears about changes; seed what is already true.
      _watchdog.update(outputEnabled: engine.videoOutputEnabled);
    } else {
      await guardedOpen(engine, session.playbackPath, log, startAt: startAt);
    }
    if (seq == _openSeq) unawaited(refreshStatus());
  }

  Future<void> _onStall() async {
    final session = _session;
    if (session == null) return;
    final seq = _openSeq;
    final engine = _engine;
    // Re-check at fire time: anything that makes "no frame" expected means
    // this is not the decoder's fault.
    if (!engine.hasVideoTrack) return;
    if (!engine.videoOutputEnabled) return;
    if (engine.videoSize != null) return;
    final active = await engine.activeHwdec();
    if (!isHardwareActive(active)) return;
    if (seq != _openSeq) return;
    await _setHwdec(DecoderMode.software.mpvHwdec);
    await _kickFrame();
    await _fallBack(session,
        'no frame after ${_ref.read(settingsProvider).decoderStallSeconds}s '
        '(hwdec-current=$active)');
  }

  /// Remembers software for [session], logs KV-504 and tells the screen.
  Future<void> _fallBack(VideoSession session, String reason) async {
    await _storeOverride(session.resumeKey, DecoderMode.software.id);
    _ref.read(errorLogProvider).record(KivoFailure(KivoOp.decoderFallback, reason));
    _ref.read(decoderFallbackEventProvider.notifier).state =
        DecoderFallbackEvent(session.resumeKey, ++_fallbackSeq);
    await refreshStatus();
  }

  /// The user picked [mode] for the current video from the player.
  Future<void> choose(DecoderMode mode) async {
    final session = _session;
    if (session == null) return;
    final global = _ref.read(settingsProvider).decoderMode;
    // Their explicit pick: the watchdog must not second-guess it.
    _watchdog.disarm();
    await _storeOverride(session.resumeKey, overrideFor(mode, global: global));
    await _switchLive(mode.mpvHwdec);
  }

  /// "Deshacer" on the fallback toast: back to hardware, stored as an explicit
  /// hardware choice — not automatic, or the watchdog would fire again on the
  /// next open and the toast would come back forever.
  Future<void> undoFallback() async {
    final session = _session;
    if (session == null) return;
    final global = _ref.read(settingsProvider).decoderMode;
    _watchdog.disarm();
    await _storeOverride(
        session.resumeKey, overrideFor(DecoderMode.hardware, global: global));
    await _switchLive(DecoderMode.hardware.mpvHwdec);
  }

  /// Drops every video's own decoder. Returns how many there were. The video
  /// playing right now keeps its decoder until it is reopened.
  Future<int> forgetAll() async {
    final store = _prefs;
    var count = 0;
    for (final entry in store.all().entries) {
      if (entry.value.decoder == null) continue;
      await store.put(entry.key, entry.value.copyWith(decoder: null));
      count++;
    }
    await refreshStatus();
    return count;
  }

  /// Re-reads what mpv is decoding with, for the decoder row.
  Future<void> refreshStatus() async {
    final session = _session;
    final notifier = _ref.read(decoderStatusProvider.notifier);
    if (session == null) {
      notifier.state = null;
      return;
    }
    String? active;
    try {
      active = await _engine.activeHwdec();
    } catch (_) {
      active = null;
    }
    if (!identical(session, _session)) return;
    notifier.state = DecoderStatus(
      mode: _modeFor(session.resumeKey),
      overridden: _prefs.forKey(session.resumeKey)?.decoder != null,
      active: active,
    );
  }

  Future<void> _switchLive(String hwdec) async {
    await _setHwdec(hwdec);
    await _kickFrame();
    await refreshStatus();
  }

  /// mpv reinitialises the decoder on a hwdec change; a seek to where we are
  /// makes it decode a fresh frame now instead of on the next keyframe.
  Future<void> _kickFrame() async {
    try {
      await _engine.seek(_lastPosition);
    } catch (e) {
      debugPrint('DecoderController seek after switch failed: $e');
    }
  }

  Future<void> _setHwdec(String value) async {
    try {
      await _engine.setHwdec(value);
    } catch (e) {
      // Never let the decoder policy break playback start.
      debugPrint('DecoderController.setHwdec($value) failed: $e');
    }
  }

  Future<void> _storeOverride(String resumeKey, String? decoder) async {
    final store = _prefs;
    final existing = store.forKey(resumeKey) ?? const VideoTrackPrefs();
    await store.put(resumeKey, existing.copyWith(decoder: decoder));
  }

  void dispose() {
    _watchdog.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}

final decoderControllerProvider = Provider<DecoderController>((ref) {
  final c = DecoderController(ref);
  ref.onDispose(c.dispose);
  return c;
});
