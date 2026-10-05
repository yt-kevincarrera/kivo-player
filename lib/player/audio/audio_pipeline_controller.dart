import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_provider.dart';
import '../engine/playback_provider.dart';
import 'audio_pipeline.dart';
import 'equalizer.dart';
import 'equalizer_controller.dart';

/// The audio track playing now, for the menu's per-track status lines.
final currentAudioSourceProvider = StateProvider<AudioSource?>((ref) => null);

/// The one writer of every audio option Kivo controls in mpv: `af`,
/// `replaygain-fallback`, `audio-channels`, `audio-swresample-o` and
/// `ad-lavc-ac3drc`.
///
/// Remembers what it last wrote and only writes differences. That is safe
/// because these are global mpv options on the process-lifetime player (they
/// survive loadfile) and nothing else writes them, so the cache mirrors mpv —
/// and it matters, because `audio-channels`/`audio-swresample-o` reload mpv's
/// whole audio chain on every write, which would be an audible hiccup on
/// every open.
///
/// Writes are serialised: an equalizer drag, a track change and a settings
/// change can all ask at once, and mpv must end up with the last one.
class AudioPipelineController {
  AudioPipelineController(this._ref);

  final Ref _ref;
  AudioPipeline? _written;
  AudioSource? _source;
  Future<void> _chain = Future.value();
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _listening = false;

  void _ensureListening() {
    if (_listening) return;
    _listening = true;
    final engine = _ref.read(playbackEngineProvider);
    // The track list arriving (after an open) and the user switching tracks
    // both change what is playing.
    _subs.add(engine.audioTracksStream.listen((_) => _refreshSource()));
    _subs.add(engine.currentAudioTrackStream.listen((_) => _refreshSource()));
  }

  /// Recomputes and writes what changed. [equalizer] is the equalizer's own
  /// latest state when it is the one asking (it can be ahead of what the
  /// settings have persisted); otherwise its live state is read.
  Future<void> apply({EqualizerSettings? equalizer}) {
    _ensureListening();
    final next = _chain.then((_) => _apply(equalizer));
    // A failed write must not wedge every later one behind it.
    _chain = next.catchError((Object _) {});
    return next;
  }

  /// A new video opened: whatever was known about the previous one's audio
  /// no longer applies. Written again once the new track is known.
  ///
  /// Reads the track directly rather than waiting for an event: the track
  /// list may well have arrived before this is called.
  ///
  /// The chain itself is NOT re-derived for "unknown" in between: with a
  /// source-dependent chain (Realzar voces) that meant writing `af` twice
  /// right after the video started — and mpv rebuilds the audio filters on
  /// every `af` write, a gap and a resync each time. It stays as it was until
  /// this video's track is known, and changes only if that track needs it.
  Future<void> onOpen() {
    _ref.read(currentAudioSourceProvider.notifier).state = null;
    return _refreshSource();
  }

  Future<void> _refreshSource({bool always = false}) async {
    _ensureListening();
    final engine = _ref.read(playbackEngineProvider);
    ({String? codec, int? channels})? raw;
    try {
      raw = await engine.currentAudioSource();
    } catch (_) {
      raw = null;
    }
    final source =
        raw == null ? null : AudioSource(codec: raw.codec, channels: raw.channels);
    // An event with no track is the gap between two videos (the list empties
    // on unload), not a new track: acting on it would flip to the stereo
    // assumption and back, rebuilding the filter graph twice at every start.
    // Only an open resets the source.
    if (source == null && !always) return;
    // The sheet shows this video's track even when it is the same kind as
    // the last one (the chain then needs nothing).
    _ref.read(currentAudioSourceProvider.notifier).state = source;
    if (source == _source && !always) return;
    _source = source;
    await apply();
  }

  Future<void> _apply(EqualizerSettings? equalizer) async {
    final settings = _ref.read(settingsProvider);
    final next = buildAudioPipeline(
      equalizer: equalizer ?? _ref.read(equalizerProvider),
      nightMode: settings.nightMode,
      nightLevel: EnhancementLevel.fromId(settings.nightModeLevel),
      voiceBoost: settings.voiceBoost,
      voiceLevel: EnhancementLevel.fromId(settings.voiceBoostLevel),
      source: _source,
    );
    final prev = _written;
    if (prev == next) return;
    final engine = _ref.read(playbackEngineProvider);

    // Each field is committed to the cache only once the engine call
    // returned, so a call that throws is retried on the next apply. (mpv's own
    // rejections do not surface: media_kit ignores setProperty's return code,
    // which is why only values known to be valid for this build are sent.)
    var done = prev ??
        const AudioPipeline(
            // Impossible values: the first apply writes every field.
            af: '\u0000',
            gainDb: double.nan,
            forceStereo: false,
            swresample: '\u0000',
            drc: double.nan);
    try {
      if (done.af != next.af) {
        await engine.setAudioFilter(next.af);
        done = _with(done, af: next.af);
      }
      if (done.gainDb != next.gainDb) {
        await engine.setAudioGain(next.gainDb);
        done = _with(done, gainDb: next.gainDb);
      }
      if (prev == null ||
          done.forceStereo != next.forceStereo ||
          done.swresample != next.swresample) {
        await engine.setAudioDownmix(
            forceStereo: next.forceStereo, swresample: next.swresample);
        done = _with(done,
            forceStereo: next.forceStereo, swresample: next.swresample);
      }
      if (done.drc != next.drc ||
          done.heavyCompression != next.heavyCompression) {
        await engine.setDolbyDrc(next.drc,
            heavyCompression: next.heavyCompression);
        done = _with(done,
            drc: next.drc, heavyCompression: next.heavyCompression);
        // The decoder reads these at init only. A Dolby track already playing
        // must be re-created to hear the change. An unknown track is reloaded
        // too: it may well be Dolby, and the sheet would otherwise claim
        // compression the running decoder does not have. (Reloading a non-
        // Dolby track is a harmless sub-second gap.)
        if (prev != null && (_source?.isDolby ?? true)) {
          await engine.reloadAudioDecoder();
        }
      }
    } catch (e) {
      debugPrint('AudioPipelineController write failed: $e');
    } finally {
      _written = done;
    }
  }

  static AudioPipeline _with(AudioPipeline p,
          {String? af,
          double? gainDb,
          bool? forceStereo,
          String? swresample,
          double? drc,
          bool? heavyCompression}) =>
      AudioPipeline(
        af: af ?? p.af,
        gainDb: gainDb ?? p.gainDb,
        forceStereo: forceStereo ?? p.forceStereo,
        swresample: swresample ?? p.swresample,
        drc: drc ?? p.drc,
        heavyCompression: heavyCompression ?? p.heavyCompression,
      );

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}

final audioPipelineProvider = Provider<AudioPipelineController>((ref) {
  final c = AudioPipelineController(ref);
  ref.onDispose(c.dispose);
  // From creation, not from the first write: a track change that arrives
  // before anything has been applied still has to be heard.
  c._ensureListening();
  // The enhancement switches and levels: any change is heard immediately.
  ref.listen(
    settingsProvider.select((s) => (
          s.nightMode,
          s.nightModeLevel,
          s.voiceBoost,
          s.voiceBoostLevel,
        )),
    (_, __) => c.apply(),
  );
  return c;
});
