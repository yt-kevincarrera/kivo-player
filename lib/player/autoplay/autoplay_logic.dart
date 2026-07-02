/// Whether an ended video should auto-advance to the next in the queue.
bool shouldAutoplay({
  required bool enabled,
  required bool hasNext,
  required bool loopActive,
  required bool sleepStopsHere,
}) =>
    enabled && hasNext && !loopActive && !sleepStopsHere;
