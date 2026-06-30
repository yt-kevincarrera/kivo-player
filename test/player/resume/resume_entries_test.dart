import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import '../../fakes/fakes.dart';

void main() {
  test('record stores updatedAt; entries lists them', () async {
    final store = InMemoryResumeStore();
    final svc = ResumeService(store);
    await svc.record('a.mp4', const Duration(seconds: 30), const Duration(minutes: 10), 1000);
    final e = svc.entries();
    expect(e.single.key, 'a.mp4');
    expect(e.single.seconds, 30);
    expect(e.single.updatedAtMs, 1000);
  });
}
