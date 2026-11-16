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
import 'video_progress_watchdog.dart';

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

final decoderFallbackEventProvider = StateProvider<DecoderFallbackEvent?>(
  (ref) => null,
);

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
  bool _playing = false;
  bool _opening = false;
  bool _recovering = false;
  final _progressWatchdog = VideoProgressWatchdog();
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
    _subs.add(
      e.playingStream.listen((v) {
        _playing = v;
        _watchdog.update(playing: v);
        if (!v) _progressWatchdog.reset();
      }),
    );
    _subs.add(
      e.videoProgressStream.listen((sample) {
        final session = _session;
        final enabled =
            session != null &&
            !_recovering &&
            !_opening &&
            _playing &&
            e.videoOutputEnabled &&
            e.hasVideoTrack &&
            _modeFor(session.resumeKey).watched &&
            _ref.read(settingsProvider).decoderAutoFallback;
        if (_progressWatchdog.update(
          sample,
          timeout: Duration(
            seconds: _ref
                .read(settingsProvider)
                .decoderStallSeconds
                .clamp(1, 10),
          ),
          enabled: enabled,
        )) {
          unawaited(_recoverFrozenPicture());
        }
      }),
    );
    _subs.add(e.hasVideoFrameStream.listen((v) => _watchdog.update(frame: v)));
    // Its own stream, not a read piggybacking on other events: the output
    // goes off (Home, audio-only) and back on without any playing/frame event
    // to carry the change.
    _subs.add(
      e.videoOutputEnabledStream.listen(
        (v) => _watchdog.update(outputEnabled: v),
      ),
    );
    // No buffering subscription on purpose — see DecoderStallWatchdog.
  }

  DecoderMode _modeFor(String resumeKey) => resolveDecoderMode(
    global: _ref.read(settingsProvider).decoderMode,
    perVideo: _prefs.forKey(resumeKey)?.decoder,
  );

  /// Opens [session] with its decoder. Throws the same [KivoFailure]
  /// (KV-501) as [guardedOpen] when the file cannot be opened at all.
  ///
  /// [play] false loads it paused (see [PlaybackEngine.open]); the caller
  /// starts it once the video's own settings are in.
  Future<void> open(
    VideoSession session, {
    Duration startAt = Duration.zero,
    bool play = true,
  }) async {
    _ensureListening();
    _watchdog.disarm();
    _progressWatchdog.reset();
    _recovering = false;
    _opening = true;
    _session = session;
    // Where a switch should seek back to until the first position event: a
    // stalled decoder may never produce one, and seeking to the previous
    // video's last position (or 0) would throw away the resume point.
    _lastPosition = startAt;
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
    await _setHwdec(mode.mpvHwdec, beforeOpen: true);

    if (fallbackAllowed) {
      try {
        await engine.open(session.playbackPath, startAt: startAt, play: play);
      } catch (e) {
        // Superseded while failing: another video owns hwdec and the screen
        // now. Retrying would overwrite its decoder and replace it on screen.
        if (seq != _openSeq) return;
        // Hardware could not even open it. One retry in software before this
        // becomes a KV-501; the retry is the one that gets logged if it fails.
        await _setHwdec(DecoderMode.software.mpvHwdec);
        await guardedOpen(
          engine,
          session.playbackPath,
          log,
          startAt: startAt,
          play: play,
        );
        if (seq != _openSeq) return;
        _opening = false;
        await _fallBack(session, 'open failed with hwdec=${mode.mpvHwdec}: $e');
        return;
      }
      if (seq != _openSeq) return;
      _opening = false;
      _rearm();
    } else {
      await guardedOpen(
        engine,
        session.playbackPath,
        log,
        startAt: startAt,
        play: play,
      );
    }
    if (seq == _openSeq) {
      _opening = false;
      unawaited(refreshStatus());
    }
  }

  Future<void> _onStall() => _recoverPicture(startup: true);

  Future<void> _recoverFrozenPicture() => _recoverPicture(startup: false);

  bool _mayRecover(int seq, VideoSession session) =>
      seq == _openSeq &&
      !_opening &&
      _playing &&
      _engine.videoOutputEnabled &&
      _engine.hasVideoTrack &&
      _modeFor(session.resumeKey).watched &&
      _ref.read(settingsProvider).decoderAutoFallback;

  Future<void> _recoverPicture({required bool startup}) async {
    final session = _session;
    if (session == null || _recovering) return;
    final seq = _openSeq;
    if (!_engine.videoOutputEnabled) {
      if (startup) _rearm();
      return;
    }
    if (!_mayRecover(seq, session) || (startup && _engine.videoSize != null)) {
      return;
    }
    _recovering = true;
    try {
      final active = await _engine.activeHwdec();
      if (!_mayRecover(seq, session) || !isHardwareActive(active)) return;
      _watchdog.disarm();
      await _setHwdec(DecoderMode.software.mpvHwdec);
      if (!_mayRecover(seq, session)) return;
      await _kickFrame();
      if (!_mayRecover(seq, session)) return;
      await _fallBack(
        session,
        startup
            ? 'no frame after ${_ref.read(settingsProvider).decoderStallSeconds}s (hwdec-current=$active)'
            : 'video timestamp stopped while playback clock advanced (hwdec-current=$active)',
      );
    } catch (e) {
      debugPrint('DecoderController picture recovery failed: $e');
    } finally {
      if (seq == _openSeq) _recovering = false;
    }
  }

  /// Arms for the current video. Seeds the output state, since the watchdog
  /// only hears about changes.
  void _rearm() {
    final engine = _engine;
    _watchdog.arm(
      Duration(
        seconds: _ref.read(settingsProvider).decoderStallSeconds.clamp(1, 10),
      ),
      frameAlreadyShown: engine.videoSize != null,
    );
    _watchdog.update(outputEnabled: engine.videoOutputEnabled);
  }

  /// Remembers software for [session], logs KV-504 and tells the screen.
  Future<void> _fallBack(VideoSession session, String reason) async {
    final seq = _openSeq;
    // overrideFor, not a bare 'sw': with a software default the video simply
    // goes back to following it, instead of gaining a redundant override.
    await _storeOverride(
      session.resumeKey,
      overrideFor(
        DecoderMode.software,
        global: _ref.read(settingsProvider).decoderMode,
      ),
    );
    if (seq != _openSeq) return;
    _ref
        .read(errorLogProvider)
        .record(KivoFailure(KivoOp.decoderFallback, reason));
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
    _progressWatchdog.reset();
    await _storeOverride(session.resumeKey, overrideFor(mode, global: global));
    await _switchLive(mode.mpvHwdec);
  }

  /// "Deshacer" on the fallback toast: back to hardware, stored as an explicit
  /// hardware choice — not automatic, or the watchdog would fire again on the
  /// next open and the toast would come back forever.
  ///
  /// Only for the video that fell back ([resumeKey]): the toast outlives a
  /// skip to the next video, and undoing there would change the wrong one.
  Future<void> undoFallback(String resumeKey) async {
    final session = _session;
    if (session == null || session.resumeKey != resumeKey) return;
    final global = _ref.read(settingsProvider).decoderMode;
    _watchdog.disarm();
    _progressWatchdog.reset();
    await _storeOverride(
      session.resumeKey,
      overrideFor(DecoderMode.hardware, global: global),
    );
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

  Future<void> _setHwdec(String value, {bool beforeOpen = false}) async {
    try {
      await _engine.setHwdec(value, beforeOpen: beforeOpen);
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
    ++_openSeq;
    _session = null;
    _progressWatchdog.reset();
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
