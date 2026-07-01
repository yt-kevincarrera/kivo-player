import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/engine/playback_engine.dart';

void main() {
  test('MediaTrack equality is by id only', () {
    const a = MediaTrack(id: '1', title: 'A', language: 'en');
    const b = MediaTrack(id: '1', title: 'Different', language: 'es');
    const c = MediaTrack(id: '2', title: 'A', language: 'en');
    expect(a, b);
    expect(a, isNot(c));
    expect(a.hashCode, b.hashCode);
  });
}
