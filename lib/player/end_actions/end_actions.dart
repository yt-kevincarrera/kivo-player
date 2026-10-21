import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/kivo_settings.dart';
import '../../core/settings/settings_provider.dart';
import '../../platform/interfaces/media_indexer.dart';
import '../open/video_source.dart';

/// What happens after a video ends, besides (optionally) trashing it.
enum AfterEnd { keepGoing, restart, closePlayer, closeApp, screenOff }

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

  factory EndActions.saved(KivoSettings settings) => EndActions(
    trash: settings.endActionsTrash,
    after: AfterEnd.values.firstWhere(
      (a) => a.name == settings.endActionsAfter,
      orElse: () => AfterEnd.keepGoing,
    ),
  );
}

/// Session choices reset on a new queue; an enabled global profile is restored
/// instead. Queue advances preserve session choices. Only profile changes
/// (not unrelated settings) replace the current choice.
final endActionsProvider = NotifierProvider<EndActionsNotifier, EndActions>(
  EndActionsNotifier.new,
);

class EndActionsNotifier extends Notifier<EndActions> {
  @override
  EndActions build() {
    ref.listen(
      settingsProvider.select(
        (s) => (s.endActionsGlobal, s.endActionsTrash, s.endActionsAfter),
      ),
      (previous, next) {
        if (next.$1 || previous?.$1 == true) _apply(_defaults());
      },
    );
    ref.listen<VideoSession?>(currentVideoProvider, (prev, next) {
      if (next == null || prev == null || !identical(prev.queue, next.queue)) {
        state = _defaults();
      }
    });
    return _defaults();
  }

  EndActions _defaults() {
    final settings = ref.read(settingsProvider);
    return settings.endActionsGlobal
        ? EndActions.saved(settings)
        : const EndActions();
  }

  void _apply(EndActions next) {
    if (!next.trash || next.after == AfterEnd.restart) {
      ref.read(endTrashProvider.notifier).state = null;
    }
    if (next.after != state.after) {
      ref.read(afterPendingProvider.notifier).state = null;
    }
    state = next;
  }

  Future<void> _save(EndActions actions) {
    final settings = ref.read(settingsProvider);
    return ref
        .read(settingsProvider.notifier)
        .set(
          settings.copyWith(
            endActionsTrash: actions.trash,
            endActionsAfter: actions.after.name,
          ),
        );
  }

  Future<void> setGlobal(bool on, {bool useCurrent = true}) {
    final settings = ref.read(settingsProvider);
    final actions = on && useCurrent && state.isActive
        ? state
        : EndActions.saved(settings);
    return ref
        .read(settingsProvider.notifier)
        .set(
          settings.copyWith(
            endActionsGlobal: on,
            endActionsTrash: actions.trash,
            endActionsAfter: actions.after.name,
          ),
        );
  }

  Future<void> setSavedTrash(bool on) =>
      _save(EndActions.saved(ref.read(settingsProvider)).copyWith(trash: on));

  Future<void> setSavedAfter(AfterEnd after) => _save(
    EndActions.saved(
      ref.read(settingsProvider),
    ).copyWith(after: after, trash: after == AfterEnd.restart ? false : null),
  );

  // Changing the choice while a card is counting down applies to THAT
  // ending too: turning the trash off must save the file on screen, and a
  // different «Después» cancels the one that was about to run.

  Future<void> setTrash(bool on) async {
    _apply(state.copyWith(trash: on));
    if (ref.read(settingsProvider).endActionsGlobal) await _save(state);
  }

  Future<void> setAfter(AfterEnd after) async {
    _apply(
      state.copyWith(
        after: after,
        trash: after == AfterEnd.restart ? false : null,
      ),
    );
    ref.read(afterPendingProvider.notifier).state = null;
    if (ref.read(settingsProvider).endActionsGlobal) await _save(state);
  }

  Future<void> clear() async {
    state = const EndActions();
    ref.read(endTrashProvider.notifier).state = null;
    ref.read(afterPendingProvider.notifier).state = null;
    if (ref.read(settingsProvider).endActionsGlobal) await setGlobal(false);
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
  final bool restart;

  const EndPlan({
    required this.trash,
    required this.advance,
    this.after,
    this.restart = false,
  });

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
  bool sleepStop = false,
}) {
  // An A-B loop never "ends" — leave today's flow alone.
  if (loopActive) return EndPlan.nothing;
  if (actions.after == AfterEnd.restart) {
    return EndPlan(trash: false, advance: false, restart: !sleepStop);
  }
  // Repeat-video would reopen a file that was just trashed.
  final trash = actions.trash && eligible && !repeatVideo;
  if (actions.after == AfterEnd.keepGoing) {
    return EndPlan(trash: trash, advance: autoplayGo);
  }
  return EndPlan(trash: trash, advance: false, after: actions.after);
}
