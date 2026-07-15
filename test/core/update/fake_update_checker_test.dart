import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/update/update_info.dart';
import '../../fakes/fakes.dart';

void main() {
  test('FakeUpdateChecker returns its result and counts calls', () async {
    const info = UpdateInfo(
        version: '1.0.1', tagName: 'v1.0.1', apkUrl: 'u', releaseUrl: 'r', notes: 'n');
    final c = FakeUpdateChecker(result: info);
    expect(await c.fetchLatest(), info);
    expect(c.calls, 1);
    c.throwsNull = true;
    expect(await c.fetchLatest(), null);
  });
}
