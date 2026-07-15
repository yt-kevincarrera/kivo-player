import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/update/version_compare.dart';

void main() {
  test('equal versions compare to 0 (ignoring v prefix and +build)', () {
    expect(compareVersions('1.0.0', '1.0.0'), 0);
    expect(compareVersions('v1.0.0', '1.0.0'), 0);
    expect(compareVersions('1.0.0+5', '1.0.0+9'), 0);
  });

  test('orders by major, then minor, then patch', () {
    expect(compareVersions('1.0.1', '1.0.0') > 0, true);
    expect(compareVersions('1.1.0', '1.0.9') > 0, true);
    expect(compareVersions('2.0.0', '1.9.9') > 0, true);
    expect(compareVersions('1.0.0', '1.0.1') < 0, true);
  });

  test('missing segments are treated as 0', () {
    expect(compareVersions('1.2', '1.2.0'), 0);
    expect(compareVersions('1', '1.0.0'), 0);
    expect(compareVersions('1.3', '1.2.9') > 0, true);
  });

  test('non-numeric / garbage segments degrade to 0, never throw', () {
    expect(compareVersions('v1.0.0-beta', '1.0.0'), 0); // -beta stripped with build
    expect(() => compareVersions('', ''), returnsNormally);
    expect(compareVersions('', '1.0.0') < 0, true);
  });

  test('isNewer wraps compareVersions', () {
    expect(isNewer('1.0.1', '1.0.0'), true);
    expect(isNewer('1.0.0', '1.0.0'), false);
    expect(isNewer('0.9.9', '1.0.0'), false);
  });
}
