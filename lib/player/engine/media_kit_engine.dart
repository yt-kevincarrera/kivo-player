import 'dart:async';
import 'package:flutter/foundation.dart';
import '../chapters/chapter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'frame_ready.dart';
import 'playback_engine.dart';

/// Process-lifetime singleton engine.
///
/// [_player] and [_videoController] are intentionally never disposed by the
/// app: they live for the entire process lifetime. [VideoController] has no
/// public `dispose()` in media_kit_video 2.x — its native texture is released
/// only when the underlying [Player] is disposed, which happens automatically
/// when the process exits. Keeping a single cached [VideoController] ensures
/// exactly one native texture is allocated regardless of how many videos the
/// user opens in a session.
class MediaKitEngine implements PlaybackEngine {
  final Player _player = Player();

  /// Cached controller — created lazily on first call, reused for all opens.
  VideoController? _videoController;

  @override
  dynamic get nativePlayer => _player;

  @override
  Object? createVideoController() {
    _videoController ??= VideoController(_player);
    return _videoController;
  }

  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Stream<Duration> get durationStream => _player.stream.duration;
  @override
  Stream<bool> get playingStream => _player.stream.playing
      // mpv 0.36 unpauses for one frame on a forward frame-step, then pauses
      // again: to the app the video never started — no icon flicker, no
      // audio-focus grab, no notification update per step.
      .where((_) => DateTime.now().isAfter(_stepQuietUntil));

  DateTime _stepQuietUntil = DateTime.fromMillisecondsSinceEpoch(0);
  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;
  @override
  Stream<bool> get completedStream => _player.stream.completed;

  /// Mirrors our own `vid` intent so [hasVideoFrameStream] can ignore the width
  /// events that `vid=no` produces (see [frameReadyStream]).
  bool _videoOutputEnabled = true;
  final _videoOutputController = StreamController<bool>.broadcast();

  @override
  Stream<bool> get hasVideoFrameStream =>
      frameReadyStream(_player.stream.width, () => _videoOutputEnabled);

  @override
  Future<void> open(String path,
      {Duration startAt = Duration.zero, bool play = true}) async {
    _stepped = false;
    _armLoaded();
    await _player.open(Media(path, start: startAt), play: play);
  }

  // "The file just opened has been read": armed BEFORE loadfile, so the
  // events cannot slip past (see [loadedAudioTracks]).
  Completer<void>? _loaded;
  final _loadedSubs = <StreamSubscription<Object?>>[];

  void _armLoaded() {
    for (final s in _loadedSubs) {
      s.cancel();
    }
    _loadedSubs.clear();
    final c = Completer<void>();
    _loaded = c;
    void done() {
      if (!c.isCompleted) c.complete();
    }

    // open() first unloads the previous file (duration 0, pseudo-tracks
    // only): those do not count.
    _loadedSubs
      ..add(_player.stream.duration.listen((d) {
        if (d > Duration.zero) done();
      }))
      ..add(_player.stream.tracks.listen((t) {
        bool real(String id) => id != 'auto' && id != 'no';
        if (t.audio.any((a) => real(a.id)) || t.video.any((v) => real(v.id))) {
          done();
        }
      }));
  }

  @override
  Future<List<MediaTrack>> loadedAudioTracks(
      {Duration timeout = const Duration(milliseconds: 1500)}) async {
    final loaded = _loaded;
    if (loaded != null) {
      await loaded.future.timeout(timeout, onTimeout: () {});
    }
    var tracks = currentAudioTracks;
    if (tracks.isEmpty && loaded != null && loaded.isCompleted) {
      // Loaded by its duration, track list a beat behind.
      try {
        tracks = await audioTracksStream
            .firstWhere((t) => t.isNotEmpty)
            .timeout(const Duration(milliseconds: 250));
      } catch (_) {
        // No audio in this file.
      }
    }
    return tracks;
  }

  /// Frame-stepped since the last play: see [play].
  bool _stepped = false;

  @override
  Future<void> play() async {
    final native = _player.platform as NativePlayer?;
    if (_stepped && native != null) {
      _stepped = false;
      // Each forward frame-step unpauses for a moment and the audio keeps
      // going, so by now it is ahead of the picture; unpaused, mpv would sync
      // the video to it and resume from a different point than the frame on
      // screen. An exact seek to that frame puts the audio back with it.
      try {
        final at = (await native.getProperty('time-pos')).trim();
        if (at.isNotEmpty && double.tryParse(at) != null) {
          await native.command(['seek', at, 'absolute+exact']);
        }
      } catch (e) {
        debugPrint('MediaKitEngine.play resync failed: $e');
      }
    }
    await _player.play();
  }
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setRate(double rate) => _player.setRate(rate);
  @override
  Future<void> setVolume(double percent) => _player.setVolume(percent);
  @override
  Future<void> dispose() => _player.dispose();

  MediaTrack _audioToMedia(AudioTrack t) => MediaTrack(
    id: t.id,
    title: t.title,
    language: t.language,
    isDefault: t.isDefault ?? false,
    codec: t.codec,
  );

  MediaTrack? _subtitleToMedia(SubtitleTrack t) {
    // media_kit's pseudo-tracks: 'no' = explicitly off, 'auto' = nothing
    // selected (what a video with no subtitles reports). Both mean "no
    // subtitle showing" on this side of the boundary.
    if (t.id == 'no' || t.id == 'auto') return null;
    return MediaTrack(
      id: t.id,
      title: t.title,
      language: t.language,
      isDefault: t.isDefault ?? false,
      codec: t.codec,
    );
  }

  @override
  Stream<List<MediaTrack>> get audioTracksStream => _player.stream.tracks.map(
    (t) => t.audio
        .where(
          (a) => a.id != 'auto' && a.id != 'no',
        ) // pseudo-tracks, not pickable rows
        .map(_audioToMedia)
        .toList(),
  );

  @override
  Stream<List<MediaTrack>> get subtitleTracksStream =>
      _player.stream.tracks.map(
        (t) =>
            t.subtitle.map(_subtitleToMedia).whereType<MediaTrack>().toList(),
      );

  @override
  Stream<MediaTrack?> get currentAudioTrackStream =>
      _player.stream.track.map((t) => _audioToMedia(t.audio));

  @override
  Stream<MediaTrack?> get currentSubtitleTrackStream =>
      _player.stream.track.map((t) => _subtitleToMedia(t.subtitle));

  @override
  List<MediaTrack> get currentAudioTracks => _player.state.tracks.audio
      .where((a) => a.id != 'auto' && a.id != 'no')
      .map(_audioToMedia)
      .toList();

  @override
  List<MediaTrack> get currentSubtitleTracks => _player.state.tracks.subtitle
      .map(_subtitleToMedia)
      .whereType<MediaTrack>()
      .toList();

  @override
  MediaTrack? get currentAudioTrack => _audioToMedia(_player.state.track.audio);

  @override
  MediaTrack? get currentSubtitleTrack =>
      _subtitleToMedia(_player.state.track.subtitle);

  @override
  Future<void> setAudioTrack(String id) async {
    final track = _player.state.tracks.audio.firstWhere(
      (t) => t.id == id,
      orElse: () => AudioTrack.auto(),
    );
    await _player.setAudioTrack(track);
  }

  @override
  Future<void> setSubtitleTrack(String? id) async {
    if (id == null) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    final track = _player.state.tracks.subtitle.firstWhere(
      (t) => t.id == id,
      orElse: () => SubtitleTrack.no(),
    );
    await _player.setSubtitleTrack(track);
  }

  @override
  Future<void> setExternalSubtitle(String uri,
      {String? title, bool replaceCurrent = false}) async {
    if (replaceCurrent) {
      final native = _player.platform as NativePlayer?;
      try {
        // No id: mpv removes the currently selected subtitle track.
        await native?.command(['sub-remove']);
      } catch (e) {
        // Nothing to remove is fine — the add below still happens.
        debugPrint('MediaKitEngine.sub-remove failed: $e');
      }
    }
    await _player.setSubtitleTrack(SubtitleTrack.uri(uri, title: title));
  }

  @override
  Future<void> setHwdec(String value, {bool beforeOpen = false}) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    // media_kit writes its own hwdec (auto-safe) when the VideoController's
    // platform half finishes creating — asynchronously, on the first open of
    // the process. Written before that, ours would be silently overwritten
    // and a video saved as "software" would open in hardware once per launch.
    final vc = _videoController;
    if (vc != null) {
      try {
        await vc.platform.future;
      } catch (_) {
        // No video controller on this platform: nothing will overwrite us.
      }
    }
    // mpv re-creates the decoder on any write, same value included: with
    // the previous video still loaded that repainted its picture for an
    // instant before the next one opened.
    try {
      if ((await native.getProperty('hwdec')).trim() == value) return;
    } catch (_) {
      // Unknown: write it.
    }
    if (beforeOpen && _player.state.playlist.medias.isNotEmpty) {
      await _player.stop();
    }
    await native.setProperty('hwdec', value);
  }

  @override
  Future<String?> activeHwdec() async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return null;
    try {
      final v = (await native.getProperty('hwdec-current')).trim();
      return v.isEmpty ? null : v;
    } catch (e) {
      // Unavailable while nothing is loaded.
      return null;
    }
  }

  @override
  bool get hasVideoTrack => _player.state.tracks.video
      .any((v) => v.id != 'auto' && v.id != 'no');

  @override
  bool get videoOutputEnabled => _videoOutputEnabled;

  @override
  Stream<bool> get videoOutputEnabledStream => _videoOutputController.stream;

  @override
  Stream<List<String>> get subtitleTextStream => _player.stream.subtitle;

  @override
  List<String> get currentSubtitleText => _player.state.subtitle;

  @override
  Future<String?> currentSubtitleCodec() async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return null;
    try {
      final codec = (await native.getProperty('current-tracks/sub/codec')).trim();
      return codec.isEmpty ? null : codec;
    } catch (_) {
      return null; // no subtitle track selected
    }
  }

  @override
  Future<void> setSubtitleRendering({required bool mpvDraws}) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    await native.setProperty('sub-visibility', mpvDraws ? 'yes' : 'no');
  }

  @override
  Future<void> configureSubtitleFonts(
      {required String dir, required String family}) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    await native.setProperty('sub-fonts-dir', dir);
    await native.setProperty('sub-font', family);
    // media_kit's Flutter-rendering mode set sub-ass=no; ASS only keeps its
    // look with it on, and only in the file's own style with override=no.
    await native.setProperty('sub-ass', 'yes');
    await native.setProperty('sub-ass-override', 'no');
  }

  String? _secondarySubtitleId;

  @override
  String? get secondarySubtitleTrackId => _secondarySubtitleId;

  @override
  Future<void> setSecondarySubtitleTrack(String? id) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    await native.setProperty('secondary-sid', id ?? 'no');
    // Believe mpv, not the request: it refuses the primary's own track.
    try {
      final actual = (await native.getProperty('secondary-sid')).trim();
      _secondarySubtitleId =
          (actual.isEmpty || actual == 'no' || actual == 'auto') ? null : actual;
    } catch (_) {
      _secondarySubtitleId = id;
    }
  }

  @override
  Future<String?> currentSubtitleId() async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return null;
    try {
      final id = (await native.getProperty('current-tracks/sub/id')).trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setSubtitleDelay(double seconds) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    await native.setProperty('sub-delay', seconds.toStringAsFixed(3));
  }

  @override
  Future<List<MediaChapter>> chapters() async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return const [];
    try {
      // A file with no chapters costs exactly this one read — the loop below
      // never runs. Only files that actually have chapters pay for them.
      final count = int.tryParse(
        await native.getProperty('chapter-list/count'),
      );
      if (count == null || count <= 0) return const [];

      final out = <MediaChapter>[];
      for (var i = 0; i < count; i++) {
        final seconds =
            double.tryParse(await native.getProperty('chapter-list/$i/time')) ??
            0;
        final title = await native.getProperty('chapter-list/$i/title');
        out.add(
          MediaChapter(
            // mpv leaves the title empty for unnamed chapters, which is
            // common; left empty here (rather than baking in a fallback
            // string) so the UI can render its own localized
            // `l10n.chapterFallback(n)` — see chapters_sheet.dart.
            title: title.trim(),
            start: Duration(milliseconds: (seconds * 1000).round()),
          ),
        );
      }
      return out;
    } catch (e) {
      // Chapters are a navigation nicety: a file whose metadata mpv cannot
      // read still plays fine, so this degrades to "no chapters".
      debugPrint('MediaKitEngine.chapters failed: $e');
      return const [];
    }
  }

  @override
  Future<void> setAudioDelay(double seconds) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    await native.setProperty('audio-delay', seconds.toStringAsFixed(3));
  }

  @override
  Future<void> setAudioFilter(String af) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    await native.setProperty('af', af);
  }

  @override
  Future<void> setAudioGain(double db) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    await native.setProperty('replaygain-fallback', db.toStringAsFixed(2));
  }

  @override
  Future<void> setAudioDownmix(
      {required bool forceStereo, required String swresample}) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    await native.setProperty('audio-swresample-o', swresample);
    await native.setProperty(
        'audio-channels', forceStereo ? 'stereo' : 'auto-safe');
  }

  @override
  Future<void> setDolbyDrc(double scale, {bool heavyCompression = false}) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    await native.setProperty('ad-lavc-ac3drc', scale.toStringAsFixed(2));
    // Every decoder gets ad-lavc-o; one without heavy_compr just logs that it
    // could not set it.
    await native.setProperty(
        'ad-lavc-o', heavyCompression ? 'heavy_compr=1' : '');
  }

  @override
  Future<void> reloadAudioDecoder() async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    final aid = (await native.getProperty('aid')).trim();
    if (aid.isEmpty || aid == 'no') return;
    await native.setProperty('aid', 'no');
    await native.setProperty('aid', aid);
  }

  @override
  Future<({String? codec, int? channels})?> currentAudioSource() async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return null;
    try {
      final codec = (await native.getProperty('current-tracks/audio/codec')).trim();
      final channels = int.tryParse(
          (await native.getProperty('current-tracks/audio/demux-channel-count'))
              .trim());
      if (codec.isEmpty && channels == null) return null;
      return (codec: codec.isEmpty ? null : codec, channels: channels);
    } catch (e) {
      // No audio track selected (yet).
      return null;
    }
  }

  @override
  Future<void> frameStep({required bool forward}) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    _stepQuietUntil = DateTime.now().add(const Duration(milliseconds: 300));
    _stepped = true;
    await native.command([forward ? 'frame-step' : 'frame-back-step']);
  }

  @override
  Future<void> setVideoTrackEnabled(bool enabled) async {
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    // Flip the gate BEFORE the property write, so no width event can slip
    // through with the flag in the wrong state.
    _videoOutputEnabled = enabled;
    _videoOutputController.add(enabled);
    await native.setProperty('vid', enabled ? 'auto' : 'no');
  }

  @override
  Future<void> ensureVideoOutputAttached() async {
    if (!_videoOutputEnabled) return;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!shouldRetryVideoAttach(
      enabled: _videoOutputEnabled,
      hasVideoSize: videoSize != null,
    )) {
      return;
    }
    final native = _player.platform as NativePlayer?;
    if (native == null) return;
    // One retry, no loops: re-apply the property and force a frame.
    await native.setProperty('vid', 'auto');
    await _player.seek(_player.state.position);
  }

  @override
  ({int width, int height})? get videoSize {
    final w = _player.state.width;
    final h = _player.state.height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return (width: w, height: h);
  }
}
