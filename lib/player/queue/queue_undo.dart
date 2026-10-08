import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the last queue edit was — picks the undo toast's message.
enum QueueEditKind { moved, playNext, removed, shuffleReset }

/// One level of undo for the queue strip: the play order as it was before
/// the last edit. Only valid while the same video is playing ([index]) — the
/// old order may not contain whatever plays next, so moving on drops it.
class QueueUndo {
  final QueueEditKind kind;

  /// Queue index of the video that was playing when the edit was made.
  final int index;

  /// `VideoSession.order` before the edit (null = natural order).
  final List<int>? order;

  /// `VideoSession.orderEdited` before the edit.
  final bool edited;

  /// For [QueueEditKind.shuffleReset]: the shuffle setting to put back.
  final bool? shuffle;

  const QueueUndo({
    required this.kind,
    required this.index,
    required this.order,
    required this.edited,
    this.shuffle,
  });
}

/// The pending undo, or null. Written only by `CurrentVideoNotifier`; the
/// player's undo toast shows while it is set.
final queueUndoProvider = StateProvider<QueueUndo?>((ref) => null);
