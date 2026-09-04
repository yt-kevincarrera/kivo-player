// Guards the ARB pair (lib/l10n/app_es.arb — the template/source of truth —
// and lib/l10n/app_en.arb) against drifting apart: a key added to one and
// forgotten in the other, a placeholder renamed on one side only, or a key
// shipped with no @description for translators/readers. Fails the build
// instead of failing silently in `flutter gen-l10n` or at runtime.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _esPath = 'lib/l10n/app_es.arb';
const _enPath = 'lib/l10n/app_en.arb';

/// Message keys only — drops `@@locale` and the `@key` metadata blocks.
Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

/// Placeholder names used by [key]'s message. Prefers the explicit
/// `@key.placeholders` block (the authoritative source gen-l10n itself
/// reads); falls back to scanning the ICU message for `{name` tokens when a
/// key has no metadata block at all.
Set<String> _placeholdersOf(Map<String, dynamic> arb, String key) {
  final meta = arb['@$key'] as Map<String, dynamic>?;
  final declared = meta?['placeholders'] as Map<String, dynamic>?;
  if (declared != null) return declared.keys.toSet();
  final value = arb[key] as String;
  return RegExp(r'\{(\w+)').allMatches(value).map((m) => m.group(1)!).toSet();
}

void main() {
  final es = jsonDecode(File(_esPath).readAsStringSync()) as Map<String, dynamic>;
  final en = jsonDecode(File(_enPath).readAsStringSync()) as Map<String, dynamic>;

  test('app_es.arb declares @@locale es and app_en.arb declares @@locale en', () {
    expect(es['@@locale'], 'es');
    expect(en['@@locale'], 'en');
  });

  test('app_en.arb and app_es.arb expose exactly the same set of keys', () {
    final esKeys = _messageKeys(es);
    final enKeys = _messageKeys(en);
    expect(enKeys, esKeys, reason: 'a key exists on one side only — see the diff above');
  });

  test('placeholders for every key match between locales', () {
    final shared = _messageKeys(es).intersection(_messageKeys(en));
    for (final key in shared) {
      expect(
        _placeholdersOf(en, key),
        _placeholdersOf(es, key),
        reason: 'placeholders for "$key" differ between app_en.arb and app_es.arb',
      );
    }
  });

  test('every key in app_es.arb has an @key description', () {
    for (final key in _messageKeys(es)) {
      final meta = es['@$key'] as Map<String, dynamic>?;
      expect(meta, isNotNull, reason: '"$key" in app_es.arb has no @$key metadata block');
      expect(
        meta!['description'],
        isA<String>().having((d) => d.trim(), 'trimmed', isNotEmpty),
        reason: '"$key" in app_es.arb has no non-empty description',
      );
    }
  });

  test('every key in app_en.arb has an @key description', () {
    for (final key in _messageKeys(en)) {
      final meta = en['@$key'] as Map<String, dynamic>?;
      expect(meta, isNotNull, reason: '"$key" in app_en.arb has no @$key metadata block');
      expect(
        meta!['description'],
        isA<String>().having((d) => d.trim(), 'trimmed', isNotEmpty),
        reason: '"$key" in app_en.arb has no non-empty description',
      );
    }
  });
}
