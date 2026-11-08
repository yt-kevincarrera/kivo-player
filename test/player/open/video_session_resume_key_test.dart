import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kivo_player/player/open/video_source.dart';
import 'package:kivo_player/core/media/video_identity.dart';

void main() {
  test('a picker original URI keeps identity across cache copies', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final videos = c.read(currentVideoProvider.notifier);
    videos.openPath(
      '/cache/1/clip.mp4',
      originalUri: 'content://documents/one',
    );
    final key = c.read(currentVideoProvider)!.resumeKey;
    videos.openPath(
      '/cache/2/clip.mp4',
      originalUri: 'content://documents/one',
    );
    expect(c.read(currentVideoProvider)!.resumeKey, key);
    videos.openPath(
      '/cache/3/clip.mp4',
      originalUri: 'content://documents/two',
    );
    expect(c.read(currentVideoProvider)!.resumeKey, isNot(key));
  });
  test('openPath: file-picker session keys resume by location', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c
        .read(currentVideoProvider.notifier)
        .openPath('/data/.../cache/file_picker/1782833069003/clip.mp4');
    final s = c.read(currentVideoProvider)!;
    expect(s.displayName, 'clip.mp4');
    expect(s.resumeKey, videoIdentity(s.playbackPath, 'clip.mp4'));
    expect(s.resumeKey, isNot(videoIdentity('/another/clip.mp4', 'clip.mp4')));
    expect(s.queue, ['/data/.../cache/file_picker/1782833069003/clip.mp4']);
    expect(s.index, 0);
  });
}
