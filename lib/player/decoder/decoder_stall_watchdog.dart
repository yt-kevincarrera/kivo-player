import 'dart:async';

/// Notices "the clock runs but no picture ever arrives" — the hardware-decoder
/// failure mpv does not catch by itself.
///
/// Wall clock, not media time: a stuck video decoder can stall mpv's own clock
/// too, so waiting for the position to advance could wait forever. The timer
/// only runs while every condition that makes a missing frame meaningful
/// holds — playing, video output on, no frame yet — and restarts from zero
/// whenever one breaks, so a pause or a trip to the background is never
/// mistaken for a broken decoder.
///
/// Deliberately NOT gated on the engine's `buffering`: media_kit derives it
/// from mpv's `core-idle`, which stays true until the first frame is decoded.
/// Gating on it would mean never counting in exactly the case this exists
/// for. Kivo plays local files, so there is no network stall to excuse.
///
/// Pure bookkeeping: whoever owns it feeds [update] from the engine's streams
/// and decides in [onStall] whether switching is still right.
class DecoderStallWatchdog {
  DecoderStallWatchdog({required this.onStall});

  final void Function() onStall;

  Duration _timeout = const Duration(seconds: 3);
  bool _armed = false;
  bool _frameSeen = false;
  bool _playing = false;
  bool _outputEnabled = true;
  Timer? _timer;

  bool get armed => _armed;

  /// Starts watching a freshly opened video. [frameAlreadyShown] covers the
  /// race where the first frame beat the open call back.
  void arm(Duration timeout, {bool frameAlreadyShown = false}) {
    _timeout = timeout;
    _armed = !frameAlreadyShown;
    _frameSeen = frameAlreadyShown;
    _timer?.cancel();
    _timer = null;
    _sync();
  }

  void disarm() {
    _armed = false;
    _sync();
  }

  void update({bool? playing, bool? outputEnabled, bool? frame}) {
    if (playing != null) _playing = playing;
    if (outputEnabled != null) _outputEnabled = outputEnabled;
    // Only a frame arriving matters; the cover flipping back to "no frame"
    // around a seek or a background trip is not the decoder failing.
    if (frame == true) {
      _frameSeen = true;
      _armed = false;
    }
    _sync();
  }

  bool get _counting => _armed && !_frameSeen && _playing && _outputEnabled;

  void _sync() {
    if (!_counting) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer(_timeout, () {
      _timer = null;
      if (!_counting) return;
      _armed = false;
      onStall();
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
