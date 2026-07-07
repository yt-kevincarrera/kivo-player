import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_file_ops.dart';
import '../fakes/fakes.dart';

void main() {
  test('FakeMediaFileOps records batch calls', () async {
    final ops = FakeMediaFileOps()..deleteManyResult = FileOpStatus.ok;
    expect(await ops.deleteMany(['u1', 'u2']), FileOpStatus.ok);
    expect(ops.deletedManyUris.single, ['u1', 'u2']);
    await ops.shareMany(['u1', 'u2']);
    expect(ops.sharedManyUris.single, ['u1', 'u2']);
  });
}
