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
    // 595s / 600s = 99.2%, above the 97% finished threshold -> cleared
    await service.record('a', const Duration(seconds: 595), const Duration(seconds: 600));
    expect(service.positionFor('a'), isNull);
  });

  test('records exactly at the min threshold but not just below it', () async {
    await service.record('a', const Duration(seconds: 5), const Duration(minutes: 10));
    expect(service.positionFor('a'), const Duration(seconds: 5));

    await service.record('b', const Duration(milliseconds: 4999), const Duration(minutes: 10));
    expect(service.positionFor('b'), isNull);
  });
}
