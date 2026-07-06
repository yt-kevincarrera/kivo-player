import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/state/player_dismiss_state.dart';

void main() {
  test('dismissDurationMs is 240ms from a resting player (progress 0)', () {
    expect(dismissDurationMs(0), 240);
  });

  test('dismissDurationMs shrinks with progress', () {
    expect(dismissDurationMs(0.5), 120);
  });

  test('dismissDurationMs clamps to a floor of 80ms near completion', () {
    expect(dismissDurationMs(0.9), 80);
    expect(dismissDurationMs(1.0), 80);
  });

  test('PlayerDismissApi holds its callbacks', () {
    var completed = false;
    var cancelled = false;
    final api = PlayerDismissApi(
      complete: () => completed = true,
      cancel: () => cancelled = true,
    );
    api.complete();
    api.cancel();
    expect(completed, isTrue);
    expect(cancelled, isTrue);
  });
}
