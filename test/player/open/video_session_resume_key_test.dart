import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/open/video_source.dart';

void main() {
  VideoSession at(String path) =>
      VideoSession(path: path, queue: [path], index: 0);

  test('resumeKey is the basename, stable across file_picker cache dirs', () {
    final a = at('/data/user/0/dev.selector.kivo_player/cache/file_picker/1782833069003/clip.mp4');
    final b = at('/data/user/0/dev.selector.kivo_player/cache/file_picker/1782833086630/clip.mp4');
    // Different per-pick cache dirs, same file → same resume key.
    expect(a.resumeKey, 'clip.mp4');
    expect(a.resumeKey, b.resumeKey);
  });

  test('resumeKey handles a plain path and backslashes', () {
    expect(at('/storage/emulated/0/Movies/ep1.mkv').resumeKey, 'ep1.mkv');
    expect(at(r'C:\Videos\ep2.mkv').resumeKey, 'ep2.mkv');
  });
}
