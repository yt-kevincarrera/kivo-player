import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/resume/resume_service.dart';
import '../../fakes/fakes.dart';

void main() {
  late InMemoryResumeStore store;
  late ResumeService service;
  setUp(() {
    store = InMemoryResumeStore();
    service = ResumeService(store, minSeconds: 5);
  });

  test('does not record below min threshold', () async {
    await service.record('a', const Duration(seconds: 3), const Duration(minutes: 10));
    expect(service.positionFor('a'), isNull);
  });

  test('records position above threshold', () async {
    await service.record('a', const Duration(seconds: 30), const Duration(minutes: 10));
    expect(service.positionFor('a'), const Duration(seconds: 30));
  });

  test('clears when near the end (finished)', () async {
    await service.record('a', const Duration(seconds: 60), const Duration(minutes: 10));
    expect(service.positionFor('a'), isNotNull);
    // 99% of 600s = 594s -> finished
    await service.record('a', const Duration(seconds: 595), const Duration(seconds: 600));
    expect(service.positionFor('a'), isNull);
  });
}
