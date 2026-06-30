import 'dart:async';
import 'dart:typed_data';
import 'package:kivo_player/core/settings/settings_store.dart';
import 'package:kivo_player/platform/interfaces/frame_extractor.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
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

  String? openedPath;
  Duration? openedAt;
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

  @override
  Future<void> seek(Duration p) async {
    lastSeek = p;
    _pos.add(p);
  }

  @override
  Future<void> setRate(double r) async => rate = r;
  @override
  Future<void> setVolume(double percent) async => volume = percent;
  @override
  Future<void> dispose() async {
    _pos.close(); _dur.close(); _playing.close(); _buffering.close();
  }
}

class InMemoryResumeStore implements ResumeStore {
  final Map<String, int> data = {};
  @override
  int? secondsFor(String key) => data[key];
  @override
  Future<void> put(String key, int seconds) async => data[key] = seconds;
  @override
  Future<void> remove(String key) async => data.remove(key);
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
  FakeMediaIndexer([this.items = const []]);
  @override
  Future<List<VideoItem>> scan() async {
    scans++;
    return items;
  }
}
