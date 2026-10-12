import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../open/video_source.dart';

/// What happens after a video ends, besides (optionally) trashing it.
enum AfterEnd { keepGoing, closePlayer, closeApp, screenOff }

/// The «Al terminar» choice for the current queue session.
class EndActions {
  /// Send each video of the queue to the trash when it ends.
  final bool trash;
  final AfterEnd after;
  const EndActions({this.trash = false, this.after = AfterEnd.keepGoing});

  /// Anything armed — drives the chip in the controls.
  bool get isActive => trash || after != AfterEnd.keepGoing;

  EndActions copyWith({bool? trash, AfterEnd? after}) =>
      EndActions(trash: trash ?? this.trash, after: after ?? this.after);
}

/// Session-scoped: armed from the player, forgotten as soon as a different
/// queue is opened (library, playlist, file picker, vault, shortcuts). Moving
/// along the same queue keeps it — `advanceTo` carries the queue list over
/// unchanged, which is what the `identical` check relies on.
final endActionsProvider =
    NotifierProvider<EndActionsNotifier, EndActions>(EndActionsNotifier.new);

class EndActionsNotifier extends Notifier<EndActions> {
  @override
  EndActions build() {
    ref.listen<VideoSession?>(currentVideoProvider, (prev, next) {
      if (next == null || prev == null || !identical(prev.queue, next.queue)) {
        state = const EndActions();
      }
    });
    return const EndActions();
  }

  // Changing the choice while a card is counting down applies to THAT
  // ending too: turning the trash off must save the file on screen, and a
  // different «Después» cancels the one that was about to run.

  void setTrash(bool on) {
    state = state.copyWith(trash: on);
    if (!on) ref.read(endTrashProvider.notifier).state = null;
  }

  void setAfter(AfterEnd after) {
    state = state.copyWith(after: after);
    ref.read(afterPendingProvider.notifier).state = null;
  }

  void clear() {
    state = const EndActions();
    ref.read(endTrashProvider.notifier).state = null;
    ref.read(afterPendingProvider.notifier).state = null;
  }
}

/// The video that just ended and goes to the trash once it is left.
class EndTrash {
  final VideoSession session;
  final VideoItem item;
  const EndTrash(this.session, this.item);
}

/// Set when a video ends with trash planned; staged when the player moves on
/// (or runs its action). «Conservar» on the countdown card clears it, and so
/// does «Cancelar» — cancelling means nothing happens at all.
final endTrashProvider = StateProvider<EndTrash?>((ref) => null);

/// A «Después» action counting down on the card (fullscreen only).
final afterPendingProvider = StateProvider<AfterEnd?>((ref) => null);

/// Flipped by the card when its ring completes or on «Ahora».
final afterConfirmProvider = StateProvider<bool>((ref) => false);

/// What an ending does, decided once and consumed by both completion paths
/// (fullscreen and minimized).
class EndPlan {
  /// Send the video that just ended to the trash (when it is left).
  final bool trash;

  /// Go on to the next video, exactly as autoplay does today.
  final bool advance;

  /// The action to run instead of advancing; null = today's behaviour.
  final AfterEnd? after;

  const EndPlan({required this.trash, required this.advance, this.after});

  static const nothing = EndPlan(trash: false, advance: false);
}

/// The sleep timer decides WHETHER playback stops (it is folded into
/// [autoplayGo]); [EndActions.after] decides HOW it stops.
EndPlan planEnd({
  required EndActions actions,
  required bool eligible,
  required bool repeatVideo,
  required bool loopActive,
  required bool autoplayGo,
}) {
  // An A-B loop never "ends" — leave today's flow alone.
  if (loopActive) return EndPlan.nothing;
  // Repeat-video would reopen a file that was just trashed.
  final trash = actions.trash && eligible && !repeatVideo;
  if (actions.after == AfterEnd.keepGoing) {
    return EndPlan(trash: trash, advance: autoplayGo);
  }
  return EndPlan(trash: trash, advance: false, after: actions.after);
}
