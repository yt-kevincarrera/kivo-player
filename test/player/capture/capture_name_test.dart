import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/capture/capture_name.dart';

void main() {
  test('names the capture after the video and the instant', () {
    expect(
      captureFileName('El Padrino.mkv', const Duration(minutes: 12, seconds: 34)),
      'El Padrino — 12m34s.jpg',
    );
  });

  test('seconds and minutes are padded so names sort in order', () {
    expect(
      captureFileName('a.mp4', const Duration(minutes: 3, seconds: 7)),
      'a — 03m07s.jpg',
    );
  });

  test('past an hour the hour is part of the name', () {
    expect(
      captureFileName('a.mp4', const Duration(hours: 1, minutes: 2, seconds: 3)),
      'a — 1h02m03s.jpg',
    );
  });

  test('a video name with dots keeps everything but the real extension', () {
    expect(
      captureFileName('S01.E02.1080p.mkv', const Duration(seconds: 5)),
      'S01.E02.1080p — 00m05s.jpg',
    );
  });

  test('a name with no extension is used whole', () {
    expect(captureFileName('sin_extension', Duration.zero),
        'sin_extension — 00m00s.jpg');
  });

  // Two captures of the same video at the same second would collide; anywhere
  // else they cannot, because the instant is in the name.
  test('two instants of the same video produce different names', () {
    const a = Duration(seconds: 10);
    const b = Duration(seconds: 11);
    expect(captureFileName('v.mkv', a) == captureFileName('v.mkv', b), false);
  });
}
