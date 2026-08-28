import 'package:flutter_test/flutter_test.dart';
import '../../fakes/fakes.dart';

void main() {
  test('the fake engine records every delay it is handed', () async {
    final engine = FakePlaybackEngine();
    await engine.setSubtitleDelay(0.5);
    await engine.setSubtitleDelay(-0.25);
    expect(engine.subtitleDelays, [0.5, -0.25]);
  });
}
