import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_file_ops.dart';
import '../fakes/fakes.dart';

void main() {
  test('FakeMediaFileOps records calls and returns configured results', () async {
    final ops = FakeMediaFileOps()
      ..deleteResult = FileOpStatus.ok
      ..renameOutcome = const RenameOutcome(FileOpStatus.ok, newName: 'b.mp4');

    expect(await ops.delete('content://v/1'), FileOpStatus.ok);
    expect(ops.deletedUris, ['content://v/1']);

    final r = await ops.rename('content://v/1', 'b');
    expect(r.status, FileOpStatus.ok);
    expect(r.newName, 'b.mp4');
    expect(ops.renamed.single, ('content://v/1', 'b'));

    await ops.share('content://v/1');
    expect(ops.sharedUris, ['content://v/1']);
  });
}
