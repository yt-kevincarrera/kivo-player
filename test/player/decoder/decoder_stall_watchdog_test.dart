import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/decoder/decoder_stall_watchdog.dart';

void main() {
  late int stalls;
  late DecoderStallWatchdog w;

  setUp(() {
    stalls = 0;
    w = DecoderStallWatchdog(onStall: () => stalls++);
  });

  test('fires once after the timeout of playing with no frame', () {
    fakeAsync((t) {
      w.arm(const Duration(seconds: 3));
      w.update(playing: true);
      t.elapse(const Duration(milliseconds: 2900));
      expect(stalls, 0);
      t.elapse(const Duration(milliseconds: 200));
      expect(stalls, 1);
      t.elapse(const Duration(seconds: 10));
      expect(stalls, 1, reason: 'one fire per arm');
    });
  });

  test('never fires when a frame arrives in time', () {
    fakeAsync((t) {
      w.arm(const Duration(seconds: 3));
      w.update(playing: true);
      t.elapse(const Duration(seconds: 2));
      w.update(frame: true);
      t.elapse(const Duration(seconds: 10));
      expect(stalls, 0);
    });
  });

  test('a frame disarms for the rest of the session, even after pausing', () {
    fakeAsync((t) {
      w.arm(const Duration(seconds: 3));
      w.update(playing: true, frame: true);
      w.update(frame: false); // the cover flips around a seek/background trip
      w.update(playing: false);
      w.update(playing: true);
      t.elapse(const Duration(seconds: 10));
      expect(stalls, 0);
    });
  });

  test('pausing stops the clock and playing again restarts it from zero', () {
    fakeAsync((t) {
      w.arm(const Duration(seconds: 3));
      w.update(playing: true);
      t.elapse(const Duration(seconds: 2));
      w.update(playing: false);
      t.elapse(const Duration(seconds: 30));
      expect(stalls, 0);
      w.update(playing: true);
      t.elapse(const Duration(seconds: 2));
      expect(stalls, 0);
      t.elapse(const Duration(seconds: 1));
      expect(stalls, 1);
    });
  });

  test('buffering is not a stall', () {
    fakeAsync((t) {
      w.arm(const Duration(seconds: 3));
      w.update(playing: true, buffering: true);
      t.elapse(const Duration(seconds: 10));
      expect(stalls, 0);
      w.update(buffering: false);
      t.elapse(const Duration(seconds: 3));
      expect(stalls, 1);
    });
  });

  test('with the video output off (audio-only / background) nothing counts', () {
    fakeAsync((t) {
      w.arm(const Duration(seconds: 3));
      w.update(playing: true, outputEnabled: false);
      t.elapse(const Duration(seconds: 10));
      expect(stalls, 0);
    });
  });

  test('a frame already on screen at arm time never fires', () {
    fakeAsync((t) {
      w.arm(const Duration(seconds: 3), frameAlreadyShown: true);
      w.update(playing: true);
      t.elapse(const Duration(seconds: 10));
      expect(stalls, 0);
    });
  });

  test('disarm cancels a running clock', () {
    fakeAsync((t) {
      w.arm(const Duration(seconds: 3));
      w.update(playing: true);
      t.elapse(const Duration(seconds: 2));
      w.disarm();
      t.elapse(const Duration(seconds: 10));
      expect(stalls, 0);
    });
  });

  test('not armed means inert, whatever the player does', () {
    fakeAsync((t) {
      w.update(playing: true);
      t.elapse(const Duration(seconds: 10));
      expect(stalls, 0);
    });
  });

  test('re-arming for the next video starts clean', () {
    fakeAsync((t) {
      w.arm(const Duration(seconds: 3));
      w.update(playing: true, frame: true);
      w.arm(const Duration(seconds: 3)); // next video, same player
      t.elapse(const Duration(seconds: 3));
      expect(stalls, 1, reason: 'the previous video\'s frame must not count');
    });
  });
}
