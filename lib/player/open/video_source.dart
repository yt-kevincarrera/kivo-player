import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../resume/resume_service.dart';
import '../queue/file_system_lister.dart';
import '../queue/folder_queue_scanner.dart';
import '../queue/queue_order.dart';

/// An immutable snapshot of the currently-opened video and its folder queue.
///
/// [playbackPath] is the path or content:// URI that media_kit opens.
/// [displayName] is the stable human-readable file name used as the resume key.
class VideoSession {
  final String playbackPath; // file path or content:// uri opened by media_kit
  final String displayName;  // file name — the stable resume key
  final List<String> queue;  // folder playbackPaths, natural order
  final List<String> queueNames; // folder display names, parallel to queue
  final List<String> queueIds; // MediaStore ids, parallel to queue — for thumbnails
  final int index;
  final String? folder; // set only when opened from the library — enables external-subtitle discovery
  /// The effective play order — a permutation of indices into [queue], with
  /// the video that started the session first. Null means natural order
  /// (`0..queue.length-1`, i.e. shuffle is off). Generated once per session
  /// (see [CurrentVideoNotifier.openFromList] and [CurrentVideoNotifier.setShuffle])
  /// and carried forward unchanged by every other session-building method —
  /// re-drawing it on each advance would let shuffle repeat a video back-to-back.
  final List<int>? order;
  const VideoSession({
    required this.playbackPath,
    required this.displayName,
    required this.queue,
    this.queueNames = const [],
    this.queueIds = const [],
    required this.index,
    this.folder,
    this.order,
  });
  String get resumeKey => displayName;
}

final resumeServiceProvider = Provider<ResumeService>((ref) {
  throw UnimplementedError('resumeServiceProvider must be overridden');
});

final queueScannerProvider = Provider<FolderQueueScanner>(
  (ref) => FolderQueueScanner(IoFileSystemLister()),
);

/// Overridable source of randomness for [shuffledOrder], so tests can inject
/// a seeded (or otherwise deterministic) Random instead of the real one.
final queueRandomProvider = Provider<Random>((ref) => Random());

class CurrentVideoNotifier extends Notifier<VideoSession?> {
  @override
  VideoSession? build() => null;

  /// Direct session open (used by tests and future callers that construct their own session).
  void open(VideoSession session) => state = session;

  /// File-picker open: single-item queue (the picker gives a cache copy, no folder).
  void openPath(String path) {
    final name = basenameOf(path);
    state = VideoSession(
        playbackPath: path, displayName: name, queue: [path], index: 0);
  }

  /// Library open: the queue is exactly the list the user is looking at
  /// ([shown]), in its displayed order — already sorted and filtered by the
  /// active tab/sort/filter/search. Autoplay walks this order verbatim; it is
  /// NOT re-sorted by name and NOT scoped to the current folder, so a tap in a
  /// flat library view continues through every following video, crossing
  /// folders, just as they appear on screen.
  ///
  /// [at] pins the position when the caller already knows it. The URI search
  /// cannot tell two copies of the same video apart, and a playlist may hold
  /// one twice on purpose — without [at], tapping the second copy would open
  /// the session at the first, and autoplay would walk the list again from
  /// there instead of continuing past it.
  void openFromList(VideoItem current, List<VideoItem> shown, {int? at}) {
    var idx = (at != null && at >= 0 && at < shown.length)
        ? at
        : shown.indexWhere((v) => v.uri == current.uri);
    final list = idx < 0 ? <VideoItem>[current] : shown;
    if (idx < 0) idx = 0;
    final shuffle = ref.read(settingsProvider).shuffle;
    state = VideoSession(
      playbackPath: current.uri,
      displayName: current.name,
      queue: list.map((v) => v.uri).toList(),
      queueNames: list.map((v) => v.name).toList(),
      queueIds: list.map((v) => v.id).toList(),
      index: idx,
      folder: current.folder, // still the tapped video's folder — for subtitle discovery
      order: shuffle ? shuffledOrder(list.length, idx, ref.read(queueRandomProvider)) : null,
    );
  }

  /// Builds (without mutating) the session for any valid queue [index], or
  /// null if out of range. Carries the full queue (uris/names/ids), folder,
  /// and play order.
  VideoSession? sessionAt(int index) {
    final s = state;
    if (s == null || index < 0 || index >= s.queue.length) return null;
    final name = index < s.queueNames.length ? s.queueNames[index] : basenameOf(s.queue[index]);
    return VideoSession(
      playbackPath: s.queue[index],
      displayName: name,
      queue: s.queue,
      queueNames: s.queueNames,
      queueIds: s.queueIds,
      index: index,
      folder: s.folder,
      order: s.order,
    );
  }

  /// The next session under the current repeat/shuffle settings, or null
  /// when playback should stop (repeat off, at the end of the queue/order).
  ///
  /// The ONLY choke point both autoplay paths (the minimized coordinator and
  /// PlayerScreen's fullscreen completion) consume — repeat and shuffle live
  /// here so every consumer (countdown overlay, notification, mini-player)
  /// inherits them for free.
  VideoSession? peekNext() {
    final s = state;
    if (s == null) return null;
    final mode = repeatModeFor(ref.read(settingsProvider).repeatMode);
    final order = s.order ?? List<int>.generate(s.queue.length, (i) => i);
    final position = order.indexOf(s.index);
    final next = nextIndex(order: order, position: position, mode: mode);
    return next == null ? null : sessionAt(next);
  }

  /// Advance the current session to [next] (used by autoplay). Observers
  /// (notification title, etc.) react as they would to any open.
  ///
  /// Never regenerates [VideoSession.order] here — [next] already carries it
  /// forward (built via [sessionAt] or [peekNext]), and the shuffled order is
  /// meant to be drawn once per session, not re-rolled on every step.
  void advanceTo(VideoSession next) => state = next;

  /// Toggles shuffle: persists the setting AND updates the active session's
  /// play order to match, so the two never drift apart. This notifier is the
  /// only thing that reads/produces [VideoSession.order], so routing the
  /// toggle through here (rather than writing settingsProvider directly from
  /// the menu) is what keeps that true. Turning shuffle off drops the order
  /// (natural order resumes, current index unchanged); turning it on draws a
  /// fresh permutation with the current video first.
  Future<void> setShuffle(bool value) async {
    final settings = ref.read(settingsProvider);
    await ref.read(settingsProvider.notifier).set(settings.copyWith(shuffle: value));
    final s = state;
    if (s == null) return;
    state = VideoSession(
      playbackPath: s.playbackPath,
      displayName: s.displayName,
      queue: s.queue,
      queueNames: s.queueNames,
      queueIds: s.queueIds,
      index: s.index,
      folder: s.folder,
      order: value ? shuffledOrder(s.queue.length, s.index, ref.read(queueRandomProvider)) : null,
    );
  }
}

final currentVideoProvider =
    NotifierProvider<CurrentVideoNotifier, VideoSession?>(CurrentVideoNotifier.new);
