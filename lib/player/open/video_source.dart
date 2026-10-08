import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../resume/resume_service.dart';
import '../queue/file_system_lister.dart';
import '../queue/folder_queue_scanner.dart';
import '../queue/queue_order.dart';
import '../queue/queue_undo.dart';
import '../../core/diagnostics/open_trace.dart';

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
  /// The effective play order — indices into [queue], in the order they will
  /// play. Null means natural order (`0..queue.length-1`). Shuffle draws it
  /// once per session (see [CurrentVideoNotifier.open] and
  /// [CurrentVideoNotifier.setShuffle]); the queue strip's edits rewrite it
  /// and may leave videos out of it (a removed video is simply absent). Every
  /// other session-building method carries it forward unchanged — re-drawing
  /// it on each advance would let shuffle repeat a video back-to-back.
  final List<int>? order;

  /// True once the user has reordered, inserted or removed in the strip.
  final bool orderEdited;

  /// Durations in ms, parallel to [queue] — 0 or missing when unknown (the
  /// queue's time left is only shown when every later one is known).
  final List<int> queueDurationsMs;
  const VideoSession({
    required this.playbackPath,
    required this.displayName,
    required this.queue,
    this.queueNames = const [],
    this.queueIds = const [],
    required this.index,
    this.folder,
    this.order,
    this.orderEdited = false,
    this.queueDurationsMs = const [],
  });
  String get resumeKey => displayName;

  /// [order], or the natural order when there is none.
  List<int> get playOrder =>
      order ?? List<int>.generate(queue.length, (i) => i);

  /// This session with a different play order.
  VideoSession withOrder(List<int>? order, {required bool edited}) =>
      VideoSession(
        playbackPath: playbackPath,
        displayName: displayName,
        queue: queue,
        queueNames: queueNames,
        queueIds: queueIds,
        index: index,
        folder: folder,
        order: order,
        orderEdited: edited,
        queueDurationsMs: queueDurationsMs,
      );
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

  /// Direct session open (used by tests and future callers that construct
  /// their own session, e.g. the vault's multi-item queue).
  ///
  /// The single choke point that turns `settings.shuffle` into
  /// [VideoSession.order]: when the caller hands over a multi-item session
  /// with no order already drawn, and shuffle is on, one is drawn here —
  /// current video first — before the session lands in state. A caller that
  /// already supplied an [VideoSession.order] (or a 1-item queue, where
  /// shuffle is a no-op) is passed through unchanged. [openFromList] goes
  /// through this same path so there is exactly one place that decides.
  ///
  /// The queue-length check runs before reading [settingsProvider] so a
  /// single-item open (file picker, or any test session with no shuffle
  /// concerns) never requires a settings override.
  void open(VideoSession session) {
    OpenTrace.instance.begin('a file');
    _dropUndo();
    if (session.order != null || session.queue.length <= 1) {
      state = session;
      return;
    }
    final shuffle = ref.read(settingsProvider).shuffle;
    if (!shuffle) {
      state = session;
      return;
    }
    state = session.withOrder(
      shuffledOrder(session.queue.length, session.index, ref.read(queueRandomProvider)),
      edited: false,
    );
  }

  /// File-picker open: single-item queue (the picker gives a cache copy, no folder).
  void openPath(String path) {
    _dropUndo();
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
    OpenTrace.instance.begin('the library');
    var idx = (at != null && at >= 0 && at < shown.length)
        ? at
        : shown.indexWhere((v) => v.uri == current.uri);
    final list = idx < 0 ? <VideoItem>[current] : shown;
    if (idx < 0) idx = 0;
    // No order here — [open] is the single place that draws one from
    // settings.shuffle, so this and any other multi-item entry point (the
    // vault's direct open(), for one) can never disagree about shuffle.
    open(VideoSession(
      playbackPath: current.uri,
      displayName: current.name,
      queue: list.map((v) => v.uri).toList(),
      queueNames: list.map((v) => v.name).toList(),
      queueIds: list.map((v) => v.id).toList(),
      queueDurationsMs: list.map((v) => v.durationMs).toList(),
      index: idx,
      folder: current.folder, // still the tapped video's folder — for subtitle discovery
    ));
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
      orderEdited: s.orderEdited,
      queueDurationsMs: s.queueDurationsMs,
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
    final order = s.playOrder;
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
  void advanceTo(VideoSession next) {
    OpenTrace.instance.begin('the queue (strip / next / autoplay)');
    // Repeat-one re-opens the same video: its undo still applies.
    if (next.index != state?.index) _dropUndo();
    state = next;
  }

  // ── Queue strip edits ──────────────────────────────────────────────────────
  // Each rewrites only the play order and leaves one level of undo behind.

  /// Moves the card at play-order position [fromPos] to [toPos].
  void reorder(int fromPos, int toPos) {
    final s = state;
    if (s == null || fromPos == toPos) return;
    _edit(s, QueueEditKind.moved, moveInOrder(s.playOrder, fromPos, toPos));
  }

  /// Queue index [item] plays right after the current video.
  void playNext(int item) {
    final s = state;
    if (s == null || item == s.index) return;
    _edit(s, QueueEditKind.playNext, playNextInOrder(s.playOrder, s.index, item));
  }

  /// Takes queue index [item] out of the play order. Never the current video.
  void remove(int item) {
    final s = state;
    if (s == null || item == s.index) return;
    _edit(s, QueueEditKind.removed, removeFromOrder(s.playOrder, s.index, item));
  }

  void _edit(VideoSession s, QueueEditKind kind, List<int> order) {
    ref.read(queueUndoProvider.notifier).state = QueueUndo(
      kind: kind,
      index: s.index,
      order: s.order,
      edited: s.orderEdited,
    );
    state = s.withOrder(order, edited: true);
  }

  /// Puts back the play order (and, after a shuffle reset, the shuffle
  /// setting) from before the last edit. A no-op once another video plays.
  Future<void> undoQueueEdit() async {
    final undo = ref.read(queueUndoProvider);
    final s = state;
    _dropUndo();
    if (undo == null || s == null || undo.index != s.index) return;
    if (undo.shuffle != null) {
      final settings = ref.read(settingsProvider);
      await ref
          .read(settingsProvider.notifier)
          .set(settings.copyWith(shuffle: undo.shuffle));
    }
    final now = state;
    if (now == null || now.index != undo.index) return;
    state = now.withOrder(undo.order, edited: undo.edited);
  }

  void _dropUndo() => ref.read(queueUndoProvider.notifier).state = null;

  /// Toggles shuffle: persists the setting AND updates the active session's
  /// play order to match, so the two never drift apart. This notifier is the
  /// only thing that reads/produces [VideoSession.order], so routing the
  /// toggle through here (rather than writing settingsProvider directly from
  /// the menu) is what keeps that true. Turning shuffle off drops the order
  /// (natural order resumes, current index unchanged); turning it on draws a
  /// fresh permutation with the current video first.
  ///
  /// Either way it starts from the whole queue, so an order the user edited
  /// in the strip is lost — that leaves a "shuffleReset" undo behind, which
  /// puts back both the setting and the edited order.
  Future<void> setShuffle(bool value) async {
    final settings = ref.read(settingsProvider);
    final before = state;
    await ref.read(settingsProvider.notifier).set(settings.copyWith(shuffle: value));
    final s = state;
    if (s == null) return;
    if (before != null && before.orderEdited && before.index == s.index) {
      ref.read(queueUndoProvider.notifier).state = QueueUndo(
        kind: QueueEditKind.shuffleReset,
        index: s.index,
        order: before.order,
        edited: true,
        shuffle: !value,
      );
    }
    state = s.withOrder(
      value ? shuffledOrder(s.queue.length, s.index, ref.read(queueRandomProvider)) : null,
      edited: false,
    );
  }
}

final currentVideoProvider =
    NotifierProvider<CurrentVideoNotifier, VideoSession?>(CurrentVideoNotifier.new);
