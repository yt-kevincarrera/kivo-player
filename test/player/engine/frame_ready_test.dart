import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/engine/frame_ready.dart';

void main() {
  test('a positive width means the open media has a decoded frame', () async {
    final widths = StreamController<int?>();
    final seen = <bool>[];
    frameReadyStream(widths.stream, () => true).listen(seen.add);
    widths.add(null);
    widths.add(1920);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [false, true]);
    await widths.close();
  });

  test('width events are dropped while the video output is intentionally off',
      () async {
    final widths = StreamController<int?>();
    var enabled = true;
    final seen = <bool>[];
    frameReadyStream(widths.stream, () => enabled).listen(seen.add);
    widths.add(1920);
    await Future<void>.delayed(Duration.zero);
    // vid=no: mpv nulls the width, but the cover belongs to the open sequence —
    // this must NOT arm it.
    enabled = false;
    widths.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [true]);
    // Reattached: real events flow again.
    enabled = true;
    widths.add(1280);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [true, true]);
    await widths.close();
  });

  test('shouldRetryVideoAttach: only when enabled and mpv reports no size', () {
    expect(shouldRetryVideoAttach(enabled: true, hasVideoSize: false), true);
    expect(shouldRetryVideoAttach(enabled: true, hasVideoSize: true), false);
    expect(shouldRetryVideoAttach(enabled: false, hasVideoSize: false), false);
  });
}
