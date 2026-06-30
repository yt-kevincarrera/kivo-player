import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/format.dart';

void main() {
  test('fmtDuration', () {
    expect(fmtDuration(const Duration(seconds: 65)), '01:05');
    expect(fmtDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });
  test('fmtSize formats MB and GB correctly', () {
    expect(fmtSize(49 * 1048576), '49.00 MB');
    expect(fmtSize(100 * 1048576), '100 MB');
    expect(fmtSize(150 * 1048576), '150 MB');
    expect(fmtSize(1024 * 1048576), '1.00 GB');
    expect(fmtSize((2 * 1024 * 1048576)), '2.00 GB');
  });
  test('basenameOf handles both separators and null', () {
    expect(basenameOf('/movies/ep1.mkv'), 'ep1.mkv');
    expect(basenameOf(r'C:\v\ep2.mp4'), 'ep2.mp4');
    expect(basenameOf(null), 'Kivo');
  });
}
