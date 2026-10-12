import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/settings_provider.dart';
import '../autoplay/autoplay_logic.dart';
import '../library/media_index.dart';
import '../loop/ab_loop.dart';
import '../open/video_source.dart';
import '../queue/queue_order.dart';
import '../sleep/sleep_timer.dart';
import 'end_actions.dart';
import 'trash_queue.dart';

// The countdown state lives with the choice it depends on.
export 'end_actions.dart';

/// Bumped by «Terminar ya»: run the ending now, without a countdown.
final finishNowProvider = StateProvider<int>((ref) => 0);

/// Bumped by «Papelera y siguiente»: one-off trash + next.
final trashAndNextProvider = StateProvider<int>((ref) => 0);

/// Set while Kivo closes itself: leaving the player then must not pop the
/// batched consent dialog — the pending ones are asked about next time.
final suppressTrashFlushProvider = StateProvider<bool>((ref) => false);

/// How Kivo leaves when «Cerrar Kivo» runs. Overridable in tests.
final appExitProvider = Provider<void Function()>(
    (ref) => () => SystemNavigator.pop());

/// Everything both completion paths need to know about an ending.
class EndDecision {
  final EndPlan plan;
  final VideoSession? next;
  final EndTrash? trash;
  final bool sleepStop;
  final bool loopActive;
  final bool autoplayEnabled;
  const EndDecision({
    required this.plan,
    required this.next,
    required this.trash,
    required this.sleepStop,
    required this.loopActive,
    required this.autoplayEnabled,
  });
}

/// [sleepStopped]: the sleep timer's episode mode already stopped this video
/// (its own state is gone by now, so it can't be asked).
EndDecision decideEnd(
  T Function<T>(ProviderListenable<T>) read, {
  required VideoSession session,
  bool sleepStopped = false,
}) {
  final settings = read(settingsProvider);
  final loopActive = read(abLoopProvider)?.phase == AbLoopPhase.active;
  final sleepStop = sleepStopped || sleepStopsHere(read(sleepTimerProvider));
  final next = read(currentVideoProvider.notifier).peekNext();
  final go = shouldAutoplay(
    enabled: settings.autoplayNext,
    hasNext: next != null,
    loopActive: loopActive,
    sleepStopsHere: sleepStop,
  );
  final item = libraryItemIn(read(mediaIndexProvider).valueOrNull, session);
  final plan = planEnd(
    actions: read(endActionsProvider),
    eligible: item != null,
    // Repeat-list wrapping onto this same video (a one-video queue, or one
    // the trash already emptied) replays it just like repeat-video does.
    repeatVideo: repeatModeFor(settings.repeatMode) == RepeatMode.video ||
        next?.index == session.index,
    loopActive: loopActive,
    autoplayGo: go,
  );
  return EndDecision(
    plan: plan,
    next: next,
    trash: plan.trash && item != null ? EndTrash(session, item) : null,
    sleepStop: sleepStop,
    loopActive: loopActive,
    autoplayEnabled: settings.autoplayNext,
  );
}
