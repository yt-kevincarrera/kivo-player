import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/queue/folder_queue_scanner.dart';
import '../../fakes/fakes.dart';

void main() {
  test('returns only video siblings, naturally sorted', () {
    final lister = FakeFileSystemLister({
      '/movies': [
        '/movies/ep10.mkv',
        '/movies/ep2.mkv',
        '/movies/notes.txt',
        '/movies/ep1.mp4',
        '/movies/cover.jpg',
      ],
    });
    final scanner = FolderQueueScanner(lister);
    final result = scanner.siblingsOf('/movies/ep2.mkv');
    expect(result, [
      '/movies/ep1.mp4',
      '/movies/ep2.mkv',
      '/movies/ep10.mkv',
    ]);
  });

  test('handles backslash paths and uppercase extensions', () {
    final lister = FakeFileSystemLister({
      r'C:\Videos': [
        r'C:\Videos\b.MKV',
        r'C:\Videos\a.Mp4',
        r'C:\Videos\readme.TXT',
      ],
    });
    final scanner = FolderQueueScanner(lister);
    final result = scanner.siblingsOf(r'C:\Videos\b.MKV');
    expect(result, [r'C:\Videos\a.Mp4', r'C:\Videos\b.MKV']);
  });
}
