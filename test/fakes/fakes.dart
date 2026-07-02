import 'dart:async';
import 'dart:typed_data';
import 'package:kivo_player/core/settings/settings_store.dart';
import 'package:kivo_player/platform/interfaces/frame_extractor.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/subtitle_finder.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/queue/file_system_lister.dart';
import 'package:kivo_player/player/resume/resume_store.dart';

class InMemorySettingsStore implements SettingsStore {
  Map<String, dynamic>? _data;
  @override
  Map<String, dynamic>? read() => _data;
  @override
  Future<void> write(Map<String, dynamic> data) async => _data = data;
}

class FakePlaybackEngine implements PlaybackEngine {
  final _pos = StreamController<Duration>.broadcast();
  final _dur = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _audioTracks = StreamController<List<MediaTrack>>.broadcast();
  final _subtitleTracks = StreamController<List<MediaTrack>>.broadcast();
  final _currentAudio = StreamController<MediaTrack?>.broadcast();
  final _currentSubtitle = StreamController<MediaTrack?>.broadcast();
  String? currentAudioTrackId;
  String? currentSubtitleTrackId; // null = off
  String? externalSubtitleUri;

  String? openedPath;
  Duration? openedAt;
  int openCount = 0;
  Duration? lastSeek;
  bool? lastPlayingCommand;
  double rate = 1.0;
  double volume = 100;

  @override
  dynamic get nativePlayer => null;
  @override
  Object? createVideoController() => null;
  @override
  Stream<Duration> get positionStream => _pos.stream;
  @override
  Stream<Duration> get durationStream => _dur.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<bool> get bufferingStream => _buffering.stream;

  void emitPosition(Duration d) => _pos.add(d);
  void emitDuration(Duration d) => _dur.add(d);
  void emitPlaying(bool v) => _playing.add(v);

  @override
  Future<void> open(String path, {Duration startAt = Duration.zero}) async {
    openedPath = path;
    openedAt = startAt;
    openCount++;
  }

  @override
  Future<void> play() async {
    lastPlayingCommand = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    lastPlayingCommand = false;
    _playing.add(false);
  }

  int seekCount = 0;

  @override
  Future<void> seek(Duration p) async {
    lastSeek = p;
    seekCount++;
    _pos.add(p);
  }

  @override
  Future<void> setRate(double r) async => rate = r;
  @override
  Future<void> setVolume(double percent) async => volume = percent;
  @override
  Future<void> dispose() async {
    _pos.close(); _dur.close(); _playing.close(); _buffering.close();
    _audioTracks.close();
    _subtitleTracks.close();
    _currentAudio.close();
    _currentSubtitle.close();
  }

  @override
  Stream<List<MediaTrack>> get audioTracksStream => _audioTracks.stream;
  @override
  Stream<List<MediaTrack>> get subtitleTracksStream => _subtitleTracks.stream;
  @override
  Stream<MediaTrack?> get currentAudioTrackStream => _currentAudio.stream;
  @override
  Stream<MediaTrack?> get currentSubtitleTrackStream => _currentSubtitle.stream;

  void emitAudioTracks(List<MediaTrack> t) => _audioTracks.add(t);
  void emitSubtitleTracks(List<MediaTrack> t) => _subtitleTracks.add(t);
  void emitCurrentAudio(MediaTrack? t) => _currentAudio.add(t);
  void emitCurrentSubtitle(MediaTrack? t) => _currentSubtitle.add(t);

  @override
  Future<void> setAudioTrack(String id) async {
    currentAudioTrackId = id;
  }

  @override
  Future<void> setSubtitleTrack(String? id) async {
    currentSubtitleTrackId = id;
  }

  @override
  Future<void> setExternalSubtitle(String uri, {String? title}) async {
    externalSubtitleUri = uri;
    currentSubtitleTrackId = uri;
  }

  double? lastSubtitleFontSize;
  int? lastSubtitleTextColorArgb;
  int? lastSubtitleBackgroundColorArgb;

  @override
  Future<void> setSubtitleStyle({
    required double fontSize,
    required int textColorArgb,
    required int backgroundColorArgb,
  }) async {
    lastSubtitleFontSize = fontSize;
    lastSubtitleTextColorArgb = textColorArgb;
    lastSubtitleBackgroundColorArgb = backgroundColorArgb;
  }
}

class InMemoryResumeStore implements ResumeStore {
  final Map<String, ResumeEntry> _m = {};
  @override
  int? secondsFor(String key) => _m[key]?.seconds;
  @override
  Future<void> put(String key, int seconds, int updatedAtMs) async =>
      _m[key] = ResumeEntry(key, seconds, updatedAtMs);
  @override
  Future<void> remove(String key) async => _m.remove(key);
  @override
  List<ResumeEntry> entries() => _m.values.toList();
}

class FakeFileSystemLister implements FileSystemLister {
  final Map<String, List<String>> dirs;
  FakeFileSystemLister(this.dirs);
  @override
  List<String> listFiles(String dir) => dirs[dir] ?? const [];
}

class FakeFrameExtractor implements FrameExtractor {
  final List<Duration> requested = [];
  String? preparedPath;
  bool released = false;
  bool autoComplete = true;
  final List<Completer<Uint8List?>> _pending = [];

  @override
  Future<void> prepare(String path) async => preparedPath = path;

  @override
  Future<void> release() async => released = true;

  @override
  Future<Uint8List?> frameAt(Duration position) {
    requested.add(position);
    if (autoComplete) {
      return Future.value(Uint8List.fromList([position.inSeconds & 0xff]));
    }
    final c = Completer<Uint8List?>();
    _pending.add(c);
    return c.future;
  }

  /// Complete the oldest outstanding manual request with bytes tagged [tag].
  void completeNext(int tag) => _pending.removeAt(0).complete(Uint8List.fromList([tag & 0xff]));
}

class FakeMediaIndexer implements MediaIndexer {
  List<VideoItem> items;
  int scans = 0;
  Uint8List? thumb;
  FakeMediaIndexer([this.items = const []]);
  @override
  Future<List<VideoItem>> scan() async {
    scans++;
    return items;
  }
  @override
  Future<Uint8List?> thumbnail(String id) async => thumb;
}

class FakeSubtitleFinder implements SubtitleFinder {
  Map<String, List<ExternalSubtitle>> byFolder = {};
  List<String> requestedFolders = [];
  @override
  Future<List<ExternalSubtitle>> findNear(String folder) async {
    requestedFolders.add(folder);
    return byFolder[folder] ?? const [];
  }
}
