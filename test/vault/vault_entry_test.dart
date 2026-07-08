// test/vault/vault_entry_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/vault/vault_entry.dart';

void main() {
  const e = VaultEntry(
    id: '42',
    privatePath: '/data/vault/42.mp4',
    displayName: 'clip.mp4',
    originalRelativePath: 'Movies/',
    durationMs: 1000,
    sizeBytes: 2000,
    dateAddedMs: 3000,
    width: 1920,
    height: 1080,
  );

  test('round-trips through toMap/fromMap', () {
    final back = VaultEntry.fromMap(e.toMap());
    expect(back.id, '42');
    expect(back.privatePath, '/data/vault/42.mp4');
    expect(back.displayName, 'clip.mp4');
    expect(back.originalRelativePath, 'Movies/');
    expect(back.durationMs, 1000);
    expect(back.sizeBytes, 2000);
    expect(back.dateAddedMs, 3000);
    expect(back.width, 1920);
    expect(back.height, 1080);
  });

  test('fromMap tolerates a Map<dynamic,dynamic> (Hive read) and missing ints', () {
    final raw = <dynamic, dynamic>{
      'id': '7',
      'privatePath': '/p/7.mkv',
      'displayName': '7.mkv',
      'originalRelativePath': '',
    };
    final entry = VaultEntry.fromMap(Map<String, dynamic>.from(raw));
    expect(entry.id, '7');
    expect(entry.durationMs, 0);
    expect(entry.width, 0);
  });
}
