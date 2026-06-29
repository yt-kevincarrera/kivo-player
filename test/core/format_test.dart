import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/format.dart';

void main() {
  test('fmtDuration', () {
    expect(fmtDuration(const Duration(seconds: 65)), '01:05');
    expect(fmtDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });
  test('basenameOf handles both separators and null', () {
    expect(basenameOf('/movies/ep1.mkv'), 'ep1.mkv');
    expect(basenameOf(r'C:\v\ep2.mp4'), 'ep2.mp4');
    expect(basenameOf(null), 'Kivo');
  });
}
