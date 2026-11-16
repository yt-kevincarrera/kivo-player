import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/engine/native_video_probe.dart';

void main() {
  test(
    'an unavailable optional library reports failure and closes its worker',
    () async {
      final probe = NativeVideoProbe(
        library: 'kivo-nonexistent-probe-library',
        handle: 0,
      );
      await expectLater(probe.start(), throwsStateError);
      await probe.dispose();
    },
  );
}
