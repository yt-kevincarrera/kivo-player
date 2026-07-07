import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/platform/interfaces/media_indexer.dart';

void main() {
  test('VideoItem new fields default to 0/empty and are optional', () {
    const v = VideoItem(
      id: '1', uri: 'content://v/1', name: 'a.mp4', folder: 'Movies',
      durationMs: 1000, sizeBytes: 10, dateAddedMs: 0,
    );
    expect(v.width, 0);
    expect(v.height, 0);
    expect(v.path, '');
  });

  test('VideoItem accepts explicit width/height/path', () {
    const v = VideoItem(
      id: '1', uri: 'content://v/1', name: 'a.mp4', folder: 'Movies',
      durationMs: 1000, sizeBytes: 10, dateAddedMs: 0,
      width: 1920, height: 1080, path: 'Movies/',
    );
    expect(v.width, 1920);
    expect(v.height, 1080);
    expect(v.path, 'Movies/');
  });
}
