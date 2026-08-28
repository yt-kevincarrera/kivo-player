import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';
import 'package:kivo_player/player/tracks/subtitle_importer.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('kivo_subs'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('KV-502 exists for a failed subtitle load', () {
    expect(kivoErrorCatalog[KivoOp.subtitleLoad]!.code, 'KV-502');
  });

  test('copies the picked file into app storage, keyed by the video', () async {
    final src = File('${tmp.path}/whatever.srt')..writeAsStringSync('1\n');
    final dest = Directory('${tmp.path}/subs');
    final importer = FileSubtitleImporter(dest);

    final path = await importer.importFor('ep1.mkv', src.path);

    expect(path, isNotNull);
    expect(File(path!).existsSync(), true);
    expect(path.endsWith('.srt'), true);
    expect(path.contains('ep1.mkv'), true);
    expect(File(path).readAsStringSync(), '1\n');
  });

  test('re-importing for the same video replaces the previous copy', () async {
    final dest = Directory('${tmp.path}/subs');
    final importer = FileSubtitleImporter(dest);
    final a = File('${tmp.path}/a.srt')..writeAsStringSync('A');
    final b = File('${tmp.path}/b.srt')..writeAsStringSync('B');

    await importer.importFor('ep1.mkv', a.path);
    final second = await importer.importFor('ep1.mkv', b.path);

    expect(File(second!).readAsStringSync(), 'B');
    expect(dest.listSync().length, 1);
  });

  test('a missing source degrades to null instead of throwing', () async {
    final importer = FileSubtitleImporter(Directory('${tmp.path}/subs'));
    expect(await importer.importFor('ep1.mkv', '${tmp.path}/ghost.srt'), isNull);
  });

  test('discard removes the copy', () async {
    final dest = Directory('${tmp.path}/subs');
    final importer = FileSubtitleImporter(dest);
    final src = File('${tmp.path}/a.srt')..writeAsStringSync('A');
    final path = await importer.importFor('ep1.mkv', src.path);

    await importer.discard(path!);
    expect(File(path).existsSync(), false);
  });

  test(
      'importing for a video whose name is a dotted prefix of another does '
      'not delete the other video\'s copy', () async {
    final dest = Directory('${tmp.path}/subs');
    final importer = FileSubtitleImporter(dest);
    final a = File('${tmp.path}/a.srt')..writeAsStringSync('A');
    final b = File('${tmp.path}/b.srt')..writeAsStringSync('B');

    // 'ep1.mkv.backup' starts with 'ep1.mkv.' -- a naive prefix match on the
    // stored filename would wrongly treat its imported copy as belonging to
    // 'ep1.mkv' and delete it on the next import for 'ep1.mkv'.
    final other = await importer.importFor('ep1.mkv.backup', a.path);
    await importer.importFor('ep1.mkv', b.path);

    expect(File(other!).existsSync(), true);
    expect(dest.listSync().length, 2);
  });
}
