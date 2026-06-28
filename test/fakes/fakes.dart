import 'dart:async';
import 'package:kivo_player/core/settings/settings_store.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
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
  double rate = 1.0;
  double volume = 100;

  @override
  dynamic get nativePlayer => null;
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
  Future<void> play() async => _playing.add(true);
  @override
  Future<void> pause() async => _playing.add(false);
  @override
  Future<void> seek(Duration p) async => _pos.add(p);
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
