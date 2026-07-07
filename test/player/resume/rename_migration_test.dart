import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/library/played.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import '../../fakes/fakes.dart';

void main() {
  test('PlayedStore.remove deletes a key', () async {
    final p = InMemoryPlayedStore();
    await p.markPlayed('a.mp4');
    expect(p.isPlayed('a.mp4'), true);
    await p.remove('a.mp4');
    expect(p.isPlayed('a.mp4'), false);
  });

  test('ResumeService.rename moves the entry preserving seconds+timestamp', () async {
    final store = InMemoryResumeStore();
    final svc = ResumeService(store);
    await store.put('old.mp4', 42, 111);
    await svc.rename('old.mp4', 'new.mp4');
    expect(svc.positionFor('old.mp4'), isNull);
    expect(svc.positionFor('new.mp4'), const Duration(seconds: 42));
    final e = svc.entries().firstWhere((x) => x.key == 'new.mp4');
    expect(e.updatedAtMs, 111); // timestamp preserved (no jump to top)
  });

  test('ResumeService.rename is a no-op when the source has no entry', () async {
    final svc = ResumeService(InMemoryResumeStore());
    await svc.rename('missing.mp4', 'x.mp4');
    expect(svc.positionFor('x.mp4'), isNull);
  });
}
