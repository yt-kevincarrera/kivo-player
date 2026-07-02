import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/pip_controller.dart';
import '../fakes/fakes.dart';

void main() {
  test('FakePipController records arm/enter/updateState/disarm and fires callbacks', () async {
    final pip = FakePipController();
    final events = <String>[];
    pip.setCallbacks(PipCallbacks(
      onModeChanged: (v) => events.add('mode:$v'),
      onPlay: () => events.add('play'),
      onPause: () => events.add('pause'),
      onSkip: (s) => events.add('skip:$s'),
    ));

    await pip.arm(width: 1920, height: 1080, playing: true);
    expect(pip.armed, true);
    expect(pip.lastWidth, 1920);
    expect(pip.lastHeight, 1080);
    expect(pip.lastPlaying, true);

    await pip.enterNow();
    expect(pip.enterCount, 1);

    await pip.updateState(width: 1280, height: 720, playing: false);
    expect(pip.lastWidth, 1280);
    expect(pip.lastPlaying, false);

    await pip.disarm();
    expect(pip.armed, false);

    // Simulate native callbacks.
    pip.emitMode(true);
    pip.emitPlay();
    pip.emitSkip(10);
    expect(events, ['mode:true', 'play', 'skip:10']);
  });
}
