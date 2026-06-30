import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/player/seek/seek_preview.dart';
import '../../../fakes/fakes.dart';

void main() {
  late FakeFrameExtractor fake;
  late List<Uint8List?> shown;
  SeekPreviewController make({int capacity = 30}) {
    fake = FakeFrameExtractor();
    shown = [];
    return SeekPreviewController(
        extractor: fake, onFrame: shown.add, capacity: capacity);
  }

  test('buckets sub-second positions to the same 1s bucket (one extraction)', () async {
    final c = make();
    c.request(const Duration(milliseconds: 1200));
    await Future<void>.delayed(Duration.zero);
    c.request(const Duration(milliseconds: 1800)); // same 1s bucket -> cache hit
    await Future<void>.delayed(Duration.zero);
    expect(fake.requested.map((d) => d.inSeconds), [1]); // only one extraction
    expect(shown.last, isNotNull);
  });

  test('LRU evicts the oldest beyond capacity', () async {
    final c = make(capacity: 2);
    for (final s in [0, 1, 2]) {
      c.request(Duration(seconds: s));
      await Future<void>.delayed(Duration.zero);
    }
    fake.requested.clear();
    c.request(const Duration(seconds: 0)); // 0 was evicted -> re-extract
    await Future<void>.delayed(Duration.zero);
    expect(fake.requested.map((d) => d.inSeconds), [0]);
    fake.requested.clear();
    c.request(const Duration(seconds: 2)); // 2 still cached -> no extraction
    await Future<void>.delayed(Duration.zero);
    expect(fake.requested, isEmpty);
  });

  test('coalesces: only one in flight, drains to the latest pending', () async {
    final c = make();
    fake.autoComplete = false;
    c.request(const Duration(seconds: 10)); // in flight (bucket 10)
    c.request(const Duration(seconds: 11)); // pending
    c.request(const Duration(seconds: 12)); // replaces pending -> 12
    expect(fake.requested.map((d) => d.inSeconds), [10]); // only first in flight
    fake.completeNext(10);
    await Future<void>.delayed(Duration.zero);
    expect(fake.requested.map((d) => d.inSeconds), [10, 12]); // drained latest, skipped 11
    fake.completeNext(12);
    await Future<void>.delayed(Duration.zero);
    expect(shown.last, Uint8List.fromList([12])); // shows the latest frame
  });
}
