import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/player/open/video_source.dart';

void main() {
  test('openPath: file-picker session keys resume by basename', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(currentVideoProvider.notifier)
        .openPath('/data/.../cache/file_picker/1782833069003/clip.mp4');
    final s = c.read(currentVideoProvider)!;
    expect(s.displayName, 'clip.mp4');
    expect(s.resumeKey, 'clip.mp4');
    expect(s.queue, ['/data/.../cache/file_picker/1782833069003/clip.mp4']);
    expect(s.index, 0);
  });
}
