import 'package:flutter_test/flutter_test.dart';
import '../fakes/fakes.dart';

void main() {
  test('FakeVaultOps.hide echoes one entry per uri and records the call', () async {
    final ops = FakeVaultOps();
    final maps = await ops.hide(['1', '2']);
    expect(maps.length, 2);
    expect(maps.first['id'], '1');
    expect(ops.hiddenUris, ['1', '2']);
  });

  test('FakeVaultOps records unhide/delete and honors result flags', () async {
    final ops = FakeVaultOps()..deleteResult = false;
    expect(await ops.unhide(['/vault/a.mp4']), true);
    expect(await ops.deleteForever(['/vault/b.mp4']), false);
    expect(ops.unhidden, ['/vault/a.mp4']);
    expect(ops.deleted, ['/vault/b.mp4']);
  });
}
