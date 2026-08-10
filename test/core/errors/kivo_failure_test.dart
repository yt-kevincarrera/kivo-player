import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/kivo_failure.dart';

void main() {
  test('every KivoOp has a catalog entry', () {
    for (final op in KivoOp.values) {
      final entry = kivoErrorCatalog[op];
      expect(entry, isNotNull, reason: 'KivoOp.${op.name} has no catalog entry');
      expect(entry!.code, isNotEmpty, reason: 'KivoOp.${op.name} has an empty code');
      expect(entry.message, isNotEmpty, reason: 'KivoOp.${op.name} has an empty message');
    }
  });

  test('codes are unique across the catalog', () {
    final seen = <String, KivoOp>{};
    for (final op in KivoOp.values) {
      final code = kivoErrorCatalog[op]!.code;
      expect(seen.containsKey(code), isFalse,
          reason: 'code $code is used by both ${seen[code]?.name} and ${op.name}');
      seen[code] = op;
    }
  });

  test('codes follow the KV-nnn format', () {
    final pattern = RegExp(r'^KV-\d{3}$');
    for (final op in KivoOp.values) {
      expect(pattern.hasMatch(kivoErrorCatalog[op]!.code), isTrue,
          reason: '${kivoErrorCatalog[op]!.code} is not KV-nnn');
    }
  });

  test('exposes the code, the message and the raw detail', () {
    const f = KivoFailure(KivoOp.libraryScan, 'no such column relative_path');
    expect(f.code, 'KV-201');
    expect(f.message, 'No pudimos leer tu biblioteca');
    expect(f.detail, contains('relative_path'));
  });

  test('toString never leaks the raw cause', () {
    const f = KivoFailure(KivoOp.libraryScan, 'no such column relative_path');
    expect(f.toString(), isNot(contains('relative_path')));
    expect(f.toString(), contains('KV-201'));
  });
}
