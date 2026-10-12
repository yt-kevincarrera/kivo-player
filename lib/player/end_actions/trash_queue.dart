import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/all_files_access_provider.dart';
import '../../platform/interfaces/media_file_ops.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../../platform/media_file_ops_provider.dart';
import '../library/video_actions.dart';
import '../open/video_source.dart';
import 'pending_trash.dart';

/// The library item behind [session], or null when it is not in the library
/// (vault, file picker copy, another app's file) — those are never trashed.
VideoItem? libraryItemIn(List<VideoItem>? index, VideoSession session) {
  if (index == null) return null;
  for (final v in index) {
    if (v.uri == session.playbackPath) return v;
  }
  return null;
}

/// The «Movido a la papelera · Deshacer» toast's payload, plus what undo needs
/// to put the video back in the play order.
class TrashUndo {
  final PendingTrash entry;

  /// Committed on its own once the toast goes (all-files access). Otherwise it
  /// waits for the batched consent dialog.
  final bool silent;

  /// Android 11+: the system trash. Below that a delete is permanent.
  final bool toTrash;

  final List<String>? queue;
  final int? index;
  final List<int>? order;
  final bool edited;

  const TrashUndo({
    required this.entry,
    required this.silent,
    required this.toTrash,
    this.queue,
    this.index,
    this.order,
    this.edited = false,
  });
}

final trashUndoProvider = StateProvider<TrashUndo?>((ref) => null);

/// How long «Deshacer» stays up before a silent commit.
final trashUndoWindowProvider =
    Provider<Duration>((_) => const Duration(seconds: 5));

/// Bumped by the mini-bar's close: leaving the session for good is a moment
/// to ask Android about the batched deletions.
final trashFlushRequestProvider = StateProvider<int>((ref) => 0);

final trashQueueProvider =
    NotifierProvider<TrashQueue, List<PendingTrash>>(TrashQueue.new);

/// Finished videos on their way to the trash. Nothing is deleted on the spot:
/// each one gets an undo window first; then it goes silently when Kivo has
/// all-files access, or waits to be confirmed in ONE system dialog for the
/// whole batch (see [flushInteractive]).
class TrashQueue extends Notifier<List<PendingTrash>> {
  final Map<String, Timer> _windows = {};
  bool _busy = false;

  /// A flush is in flight — the consent dialog pauses and resumes the
  /// activity, which must not start a second one.
  bool get busy => _busy;

  @override
  List<PendingTrash> build() {
    ref.onDispose(() {
      for (final t in _windows.values) {
        t.cancel();
      }
      _windows.clear();
    });
    return ref.read(pendingTrashStoreProvider).all();
  }

  Future<bool> isSilent() async {
    if (!ref.read(mediaFileOpsProvider).movesToTrash) return false;
    return ref.read(allFilesAccessProvider).isGranted();
  }

  /// Queues [item] for the trash. [ended] is the session that finished: when
  /// the player already moved on from it, it leaves the play order too.
  Future<void> stage(VideoItem item, {VideoSession? ended}) async {
    final entry = PendingTrash(
      uri: item.uri,
      name: item.name,
      id: item.id,
      stagedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await ref.read(pendingTrashStoreProvider).put(entry);
    state = [...state.where((e) => e.uri != entry.uri), entry];

    List<String>? queue;
    int? index;
    List<int>? order;
    var edited = false;
    final now = ref.read(currentVideoProvider);
    if (ended != null &&
        now != null &&
        identical(ended.queue, now.queue) &&
        ended.index != now.index) {
      queue = now.queue;
      index = ended.index;
      order = now.order;
      edited = now.orderEdited;
      ref.read(currentVideoProvider.notifier).dropTrashed(ended.index);
    }

    final silent = await isSilent();
    ref.read(trashUndoProvider.notifier).state = TrashUndo(
      entry: entry,
      silent: silent,
      toTrash: ref.read(mediaFileOpsProvider).movesToTrash,
      queue: queue,
      index: index,
      order: order,
      edited: edited,
    );
    _windows[entry.uri]?.cancel();
    _windows[entry.uri] =
        Timer(ref.read(trashUndoWindowProvider), () => _windowClosed(entry));
  }

  Future<void> _windowClosed(PendingTrash entry) async {
    _windows.remove(entry.uri);
    final undo = ref.read(trashUndoProvider);
    if (undo != null && undo.entry.uri == entry.uri) {
      ref.read(trashUndoProvider.notifier).state = null;
    }
    if (!state.any((e) => e.uri == entry.uri)) return; // undone meanwhile
    if (_busy || !await isSilent()) return;
    await _delete([entry]);
  }

  /// Keeps the file: out of the queue, and back in the play order.
  Future<void> undo(String uri) async {
    _windows.remove(uri)?.cancel();
    await ref.read(pendingTrashStoreProvider).remove(uri);
    state = state.where((e) => e.uri != uri).toList();
    final u = ref.read(trashUndoProvider);
    if (u == null || u.entry.uri != uri) return;
    ref.read(trashUndoProvider.notifier).state = null;
    if (u.queue != null && u.index != null) {
      ref.read(currentVideoProvider.notifier).restoreTrashed(
            queue: u.queue!,
            item: u.index!,
            previousOrder: u.order,
            previousEdited: u.edited,
          );
    }
  }

  /// Everything pending — except [loadedUri], the video still on screen in
  /// the mini-bar — in one delete: one consent dialog for the batch when
  /// Kivo lacks all-files access. The batch leaves the queue whatever the
  /// answer (declining the dialog = keeping the files). Null when there was
  /// nothing to do.
  Future<FileOpStatus?> flushInteractive({String? loadedUri}) async {
    if (_busy) return null;
    final batch = state.where((e) => e.uri != loadedUri).toList();
    if (batch.isEmpty) return null;
    for (final e in batch) {
      _windows.remove(e.uri)?.cancel();
    }
    final undo = ref.read(trashUndoProvider);
    if (undo != null && batch.any((e) => e.uri == undo.entry.uri)) {
      ref.read(trashUndoProvider.notifier).state = null;
    }
    return _delete(batch);
  }

  /// Commits, without asking, what is past its undo window — only when that
  /// needs no dialog (all-files access). For app start / return to the app.
  Future<void> commitSilentlyIfPossible({String? loadedUri}) async {
    if (_busy || !await isSilent()) return;
    final due = state
        .where((e) => e.uri != loadedUri && !_windows.containsKey(e.uri))
        .toList();
    if (due.isNotEmpty) await _delete(due);
  }

  /// «Conservar» on the pending sheet: forget them all, files untouched.
  Future<void> keepAll() async {
    final store = ref.read(pendingTrashStoreProvider);
    for (final e in state) {
      _windows.remove(e.uri)?.cancel();
      await store.remove(e.uri);
    }
    state = const [];
  }

  Future<FileOpStatus> _delete(List<PendingTrash> batch) async {
    _busy = true;
    try {
      final items = [
        for (final e in batch)
          VideoItem(
            id: e.id,
            uri: e.uri,
            name: e.name,
            folder: '',
            durationMs: 0,
            sizeBytes: 0,
            dateAddedMs: 0,
          ),
      ];
      final status = await ref.read(videoActionsProvider).deleteMany(items);
      final store = ref.read(pendingTrashStoreProvider);
      for (final e in batch) {
        await store.remove(e.uri);
      }
      final gone = batch.map((e) => e.uri).toSet();
      state = state.where((e) => !gone.contains(e.uri)).toList();
      return status;
    } finally {
      _busy = false;
    }
  }
}
