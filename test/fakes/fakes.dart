import 'dart:async';
import 'dart:typed_data';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/settings/settings_store.dart';
import 'package:kivo_player/core/update/update_checker.dart';
import 'package:kivo_player/core/update/update_info.dart';
import 'package:kivo_player/platform/interfaces/all_files_access.dart';
import 'package:kivo_player/platform/interfaces/app_installer.dart';
import 'package:kivo_player/platform/interfaces/biometric_auth.dart';
import 'package:kivo_player/platform/interfaces/frame_extractor.dart';
import 'package:kivo_player/platform/interfaces/media_file_ops.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';
import 'package:kivo_player/platform/interfaces/media_session.dart';
import 'package:kivo_player/platform/interfaces/pip_controller.dart';
import 'package:kivo_player/platform/interfaces/subtitle_finder.dart';
import 'package:kivo_player/platform/interfaces/vault_ops.dart';
import 'package:kivo_player/player/chapters/chapter.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';
import 'package:kivo_player/player/queue/file_system_lister.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import 'package:kivo_player/player/resume/resume_store.dart';
import 'package:kivo_player/player/tracks/subtitle_importer.dart';

class InMemorySettingsStore implements SettingsStore {
  Map<String, dynamic>? _data;
  @override
  Map<String, dynamic>? read() => _data;
  @override
  Future<void> write(Map<String, dynamic> data) async => _data = data;
}

class ThrowingErrorLogStore implements ErrorLogStore {
  @override
  List<Map<String, dynamic>> read() => throw StateError('read boom');
  @override
  Future<void> write(List<Map<String, dynamic>> entries) async =>
      throw StateError('write boom');
}

class FakePlaybackEngine implements PlaybackEngine {
  final _pos = StreamController<Duration>.broadcast();
  final _dur = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _audioTracks = StreamController<List<MediaTrack>>.broadcast();
  final _subtitleTracks = StreamController<List<MediaTrack>>.broadcast();
  final _currentAudio = StreamController<MediaTrack?>.broadcast();
  final _currentSubtitle = StreamController<MediaTrack?>.broadcast();
  final _frame = StreamController<bool>.broadcast();
  String? currentAudioTrackId;
  String? currentSubtitleTrackId; // null = off
  String? externalSubtitleUri;

  String? openedPath;
  Duration? openedAt;
  int openCount = 0;

  /// Set to make [open] throw — for the KV-501 path.
  Object? openError;
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
  @override
  Stream<bool> get completedStream => _completed.stream;
  @override
  Stream<bool> get hasVideoFrameStream => _frame.stream;

  void emitPosition(Duration d) => _pos.add(d);
  void emitDuration(Duration d) => _dur.add(d);
  void emitPlaying(bool v) => _playing.add(v);
  void emitCompleted(bool v) => _completed.add(v);
  void emitVideoFrame(bool v) => _frame.add(v);

  @override
  Future<void> open(String path, {Duration startAt = Duration.zero}) async {
    if (openError != null) throw openError!;
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
    _pos.close();
    _dur.close();
    _playing.close();
    _buffering.close();
    _completed.close();
    _audioTracks.close();
    _subtitleTracks.close();
    _currentAudio.close();
    _currentSubtitle.close();
    _frame.close();
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

  List<MediaTrack> subtitleTracksValue = [];
  List<MediaTrack> audioTracksValue = [];
  MediaTrack? currentSubtitleTrackValue;
  MediaTrack? currentAudioTrackValue;

  @override
  List<MediaTrack> get currentSubtitleTracks => subtitleTracksValue;
  @override
  List<MediaTrack> get currentAudioTracks => audioTracksValue;
  @override
  MediaTrack? get currentSubtitleTrack => currentSubtitleTrackValue;
  @override
  MediaTrack? get currentAudioTrack => currentAudioTrackValue;

  @override
  Future<void> setAudioTrack(String id) async {
    currentAudioTrackId = id;
  }

  @override
  Future<void> setSubtitleTrack(String? id) async {
    currentSubtitleTrackId = id;
  }

  /// Every setExternalSubtitle call as (uri, title) — the title is part of the
  /// behaviour (it is what the track picker lists), so it has to be visible.
  final List<(String, String?)> externalSubtitles = [];

  @override
  Future<void> setExternalSubtitle(String uri, {String? title}) async {
    externalSubtitleUri = uri;
    currentSubtitleTrackId = uri;
    externalSubtitles.add((uri, title));
  }

  final List<double> subtitleDelays = [];

  @override
  Future<void> setSubtitleDelay(double seconds) async =>
      subtitleDelays.add(seconds);

  final List<double> audioDelays = [];

  /// What [chapters] returns; empty is the common case on real files.
  List<MediaChapter> chaptersValue = const [];
  int chapterReads = 0;

  @override
  Future<List<MediaChapter>> chapters() async {
    chapterReads++;
    return chaptersValue;
  }

  @override
  Future<void> setAudioDelay(double seconds) async => audioDelays.add(seconds);

  final List<String> audioFilters = [];
  String? lastAudioFilter;

  /// Optional gate: when set, [setAudioFilter] awaits this completer before
  /// recording the call, so tests can hold the "native round trip" open and
  /// observe (or act during) the in-flight window before resolving it with
  /// `audioFilterGate.complete()`. Defaults to null, preserving the
  /// immediate-return behavior for existing callers.
  Completer<void>? audioFilterGate;

  @override
  Future<void> setAudioFilter(String af) async {
    if (audioFilterGate != null) await audioFilterGate!.future;
    lastAudioFilter = af;
    audioFilters.add(af);
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

  bool videoTrackEnabled = true;

  @override
  Future<void> setVideoTrackEnabled(bool enabled) async {
    videoTrackEnabled = enabled;
  }

  int ensureAttachCalls = 0;

  @override
  Future<void> ensureVideoOutputAttached() async => ensureAttachCalls++;

  ({int width, int height})? videoSizeValue;
  @override
  ({int width, int height})? get videoSize => videoSizeValue;
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
  final List<String> prepared = [];
  String? preparedPath;

  /// When set, every frameAt returns exactly this instead of the generated
  /// bytes — for asserting on what a caller did with the frame.
  Uint8List? bytes;

  /// Simulates a position with no decodable frame.
  bool returnsNull = false;

  /// Simulates MediaMetadataRetriever throwing on a broken file.
  bool throwOnFrame = false;
  bool released = false;
  bool autoComplete = true;
  final List<Completer<Uint8List?>> _pending = [];

  @override
  Future<void> prepare(String path) async {
    preparedPath = path;
    prepared.add(path);
  }

  @override
  Future<void> release() async => released = true;

  @override
  Future<Uint8List?> frameAt(Duration position) {
    requested.add(position);
    if (throwOnFrame) throw StateError("retriever boom");
    if (returnsNull) return Future.value(null);
    if (bytes != null) return Future.value(bytes);
    if (autoComplete) {
      return Future.value(Uint8List.fromList([position.inSeconds & 0xff]));
    }
    final c = Completer<Uint8List?>();
    _pending.add(c);
    return c.future;
  }

  /// Complete the oldest outstanding manual request with bytes tagged [tag].
  void completeNext(int tag) =>
      _pending.removeAt(0).complete(Uint8List.fromList([tag & 0xff]));
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

class FakeMediaSessionBridge implements MediaSessionBridge {
  MediaSessionCallbacks? callbacks;
  final List<Map<String, Object>> updates = [];
  int endCount = 0;
  int permissionRequests = 0;
  int focusAcquires = 0;
  int focusReleases = 0;

  @override
  void setCallbacks(MediaSessionCallbacks cb) => callbacks = cb;

  @override
  Future<void> ensureNotificationPermission() async => permissionRequests++;

  @override
  Future<void> updateSession({
    required String title,
    required String mediaUri,
    required Duration position,
    required Duration duration,
    required bool playing,
    required bool inBackground,
  }) async {
    updates.add({
      'title': title,
      'mediaUri': mediaUri,
      'position': position,
      'duration': duration,
      'playing': playing,
      'inBackground': inBackground,
    });
  }

  @override
  Future<void> endSession() async => endCount++;

  @override
  Future<void> acquireAudioFocus() async => focusAcquires++;

  @override
  Future<void> releaseAudioFocus() async => focusReleases++;
}

class FakePipController implements PipController {
  bool supported = true;
  bool armed = false;
  int enterCount = 0;
  int? lastWidth, lastHeight;
  bool? lastPlaying;
  PipCallbacks? _cb;

  @override
  Future<bool> isSupported() async => supported;
  @override
  void setCallbacks(PipCallbacks cb) => _cb = cb;
  @override
  Future<void> arm({
    required int width,
    required int height,
    required bool playing,
  }) async {
    armed = true;
    lastWidth = width;
    lastHeight = height;
    lastPlaying = playing;
  }

  @override
  Future<void> disarm() async => armed = false;
  @override
  Future<void> enterNow() async => enterCount++;
  @override
  Future<void> updateState({
    required int width,
    required int height,
    required bool playing,
  }) async {
    lastWidth = width;
    lastHeight = height;
    lastPlaying = playing;
  }

  void emitMode(bool inPip) => _cb?.onModeChanged(inPip);
  void emitPlay() => _cb?.onPlay();
  void emitPause() => _cb?.onPause();
  void emitSkip(int s) => _cb?.onSkip(s);
}

class FakeResumeService implements ResumeService {
  @override
  int minSeconds = 5;
  @override
  double finishedTailFraction = 0.97;

  final Map<String, Duration> positions = {};
  final List<String> recordedKeys = [];

  @override
  Duration? positionFor(String key) => positions[key];

  @override
  Future<void> record(
    String key,
    Duration position,
    Duration total,
    int nowMs,
  ) async {
    recordedKeys.add(key);
    positions[key] = position;
  }

  @override
  List<ResumeEntry> entries() => const [];

  @override
  Future<void> clear(String key) async => positions.remove(key);

  @override
  Future<void> rename(String from, String to) async {
    final pos = positions.remove(from);
    if (pos != null) {
      positions[to] = pos;
    }
  }
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

class FakeSubtitleImporter implements SubtitleImporter {
  /// What [importFor] hands back; set to null to simulate a failed copy.
  String? result = '/app/subs/ep1.mkv.srt';
  final List<(String, String)> imported = [];
  final List<String> discarded = [];

  @override
  Future<String?> importFor(String videoKey, String sourcePath) async {
    imported.add((videoKey, sourcePath));
    return result;
  }

  @override
  Future<void> discard(String importedPath) async =>
      discarded.add(importedPath);
}

class FakeMediaFileOps implements MediaFileOps {
  final List<String> deletedUris = [];
  final List<(String, String)> renamed = []; // (uri, baseName)
  final List<String> sharedUris = [];
  FileOpStatus deleteResult = FileOpStatus.ok;
  RenameOutcome renameOutcome = const RenameOutcome(
    FileOpStatus.ok,
    newName: 'renamed.mp4',
  );

  /// Defaults to false (permanent delete), matching pre-Android-11. Set true
  /// to simulate an API 30+ device where delete moves to the system trash.
  @override
  bool movesToTrash = false;

  @override
  Future<FileOpStatus> delete(String uri) async {
    deletedUris.add(uri);
    return deleteResult;
  }

  @override
  Future<RenameOutcome> rename(String uri, String newBaseName) async {
    renamed.add((uri, newBaseName));
    return renameOutcome;
  }

  @override
  Future<void> share(String uri) async => sharedUris.add(uri);

  final List<List<String>> deletedManyUris = [];
  final List<List<String>> sharedManyUris = [];
  FileOpStatus deleteManyResult = FileOpStatus.ok;

  @override
  Future<FileOpStatus> deleteMany(List<String> uris) async {
    deletedManyUris.add(List.of(uris));
    return deleteManyResult;
  }

  @override
  Future<void> shareMany(List<String> uris) async =>
      sharedManyUris.add(List.of(uris));
}

class FakeAllFilesAccess implements AllFilesAccess {
  bool granted;
  bool grantOnRequest;
  int requestCount = 0;
  FakeAllFilesAccess({this.granted = false, this.grantOnRequest = true});

  @override
  Future<bool> isGranted() async => granted;

  @override
  Future<bool> request() async {
    requestCount++;
    granted = grantOnRequest;
    return granted;
  }
}

class FakeVaultOps implements VaultOps {
  final List<String> hiddenUris = [];
  final List<String> unhidden = [];
  final List<String> deleted = [];
  bool unhideResult = true;
  bool deleteResult = true;

  /// Paths that should be reported as FAILED (omitted from the returned
  /// list) even though they are still recorded into [unhidden]/[deleted],
  /// simulating a partial-batch native failure. Empty by default (all
  /// succeed), subject to the [unhideResult]/[deleteResult] all-or-nothing
  /// flags below.
  Set<String> failPaths = {};

  /// Maps each uri -> the metadata map hide() should return. Defaults to a
  /// synthesized entry so callers can just pass uris.
  List<Map<String, dynamic>> Function(List<String> uris)? hideResult;

  @override
  Future<List<Map<String, dynamic>>> hide(List<String> uris) async {
    hiddenUris.addAll(uris);
    if (hideResult != null) return hideResult!(uris);
    return uris.map((u) {
      final id = u.split('/').last;
      return {
        'id': id,
        'privatePath': '/vault/$id.mp4',
        'displayName': '$id.mp4',
        'originalRelativePath': 'Movies/',
        'durationMs': 0,
        'sizeBytes': 0,
        'dateAddedMs': 0,
        'width': 0,
        'height': 0,
      };
    }).toList();
  }

  @override
  Future<List<String>> unhide(List<Map<String, dynamic>> entries) async {
    final paths = entries.map((e) => e['privatePath'] as String).toList();
    unhidden.addAll(paths);
    if (!unhideResult) return const <String>[];
    return paths.where((p) => !failPaths.contains(p)).toList();
  }

  @override
  Future<List<String>> deleteForever(List<String> privatePaths) async {
    deleted.addAll(privatePaths);
    if (!deleteResult) return const <String>[];
    return privatePaths.where((p) => !failPaths.contains(p)).toList();
  }

  @override
  Future<Uint8List?> thumbnail(String privatePath) async => null;

  @override
  Future<List<Map<String, dynamic>>> migrate() async => const [];
}

class FakeBiometricAuth implements BiometricAuth {
  bool available;
  bool willSucceed;
  int authCalls = 0;

  /// Optional gate: when set, [authenticate] awaits this completer instead of
  /// returning immediately, so tests can observe the "in flight" state before
  /// resolving it with `gate.complete(result)`. Defaults to null, preserving
  /// the immediate-return behavior for existing callers.
  Completer<bool>? gate;
  FakeBiometricAuth({
    this.available = true,
    this.willSucceed = true,
    this.gate,
  });
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> authenticate(BiometricAuthMessages messages) async {
    authCalls++;
    if (gate != null) return gate!.future;
    return willSucceed;
  }
}

class FakeUpdateChecker implements UpdateChecker {
  UpdateInfo? result;
  bool throwsNull = false; // when true, fetchLatest returns null (error path)
  int calls = 0;
  FakeUpdateChecker({this.result});

  @override
  Future<UpdateInfo?> fetchLatest() async {
    calls++;
    if (throwsNull) return null;
    return result;
  }
}

class FakeAppInstaller implements AppInstaller {
  String version;
  String abi;
  InstallOutcome installOutcome;

  /// Id handed out by [enqueueUpdate]; set to -1 to simulate a refused queue.
  int nextDownloadId;

  /// What [downloadStatus] reports. Tests move this to drive the controller
  /// through running → paused → done the way DownloadManager would.
  DownloadProgress status = const DownloadProgress(
    DownloadStage.running,
    received: 1,
    total: 4,
  );

  final List<(String, String)> enqueued = [];
  final List<int> cancelled = [];
  final List<int> installs = [];
  final List<String> openedUrls = [];

  FakeAppInstaller({
    this.version = '1.0.0',
    this.abi = 'arm64-v8a',
    this.installOutcome = InstallOutcome.started,
    this.nextDownloadId = 7,
  });

  @override
  Future<String> appVersion() async => version;
  @override
  Future<String> primaryAbi() async => abi;
  int sdk = 34;
  @override
  Future<int> androidSdk() async => sdk;

  @override
  Future<int> enqueueUpdate(String url, String fileName) async {
    enqueued.add((url, fileName));
    return nextDownloadId;
  }

  @override
  Future<DownloadProgress> downloadStatus(int id) async =>
      id == nextDownloadId ? status : DownloadProgress.gone;

  @override
  Future<void> cancelDownload(int id) async => cancelled.add(id);

  @override
  Future<InstallOutcome> installDownload(int id) async {
    installs.add(id);
    return installOutcome;
  }

  @override
  Future<void> openUrl(String url) async => openedUrls.add(url);
}
