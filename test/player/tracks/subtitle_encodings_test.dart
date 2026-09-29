import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/tracks/subtitle_encodings.dart';

void main() {
  test('the short list has one charset per family, all distinct', () {
    final families = curatedSubtitleEncodings.map((e) => e.family).toSet();
    expect(families.length, EncodingFamily.values.length);
    expect(curatedSubtitleEncodings.first.charset, 'UTF-8');
  });

  test('every curated charset maps back to its own family', () {
    for (final e in curatedSubtitleEncodings) {
      expect(familyOf(e.charset), e.family, reason: e.charset);
    }
  });

  test('detector spellings land in the right family, case-insensitively', () {
    expect(familyOf('ISO-8859-1'), EncodingFamily.western);
    expect(familyOf('KOI8-R'), EncodingFamily.cyrillic);
    expect(familyOf('iso-8859-5'), EncodingFamily.cyrillic);
    expect(familyOf('GB18030'), EncodingFamily.chineseSimplified);
    expect(familyOf('EUC-JP'), EncodingFamily.japanese);
    expect(familyOf('UTF-16LE'), EncodingFamily.unicode);
    expect(familyOf('ISO-8859-2'), EncodingFamily.central);
  });

  test('unknown or missing names have no family', () {
    expect(familyOf('x-IBM1047'), isNull);
    expect(familyOf(null), isNull);
  });

  test('"Más…" lists only what the short list lacks, sorted', () {
    expect(
        extraEncodings(['windows-1251', 'KOI8-R', 'utf-8', 'IBM437', 'Big5']),
        ['IBM437', 'KOI8-R']);
  });

  test('sameCharset ignores case and never matches null', () {
    expect(sameCharset('Shift_JIS', 'shift_jis'), isTrue);
    expect(sameCharset(null, 'UTF-8'), isFalse);
  });
}
