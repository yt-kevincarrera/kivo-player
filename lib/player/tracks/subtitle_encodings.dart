/// The readable groups the encoding picker speaks in. Widgets map each one to
/// its localized name; this file stays free of copy.
enum EncodingFamily {
  unicode,
  western,
  central,
  cyrillic,
  greek,
  turkish,
  hebrew,
  arabic,
  baltic,
  vietnamese,
  thai,
  chineseSimplified,
  chineseTraditional,
  japanese,
  korean,
}

/// One row of the picker's short list: the family and the charset it loads.
class CuratedEncoding {
  const CuratedEncoding(this.family, this.charset);
  final EncodingFamily family;
  final String charset;
}

/// The short list, in the order the picker shows it. One charset per family —
/// the one real-world subtitles in that script most often use; the rest are
/// under "Más…".
const curatedSubtitleEncodings = <CuratedEncoding>[
  CuratedEncoding(EncodingFamily.unicode, 'UTF-8'),
  CuratedEncoding(EncodingFamily.western, 'windows-1252'),
  CuratedEncoding(EncodingFamily.central, 'windows-1250'),
  CuratedEncoding(EncodingFamily.cyrillic, 'windows-1251'),
  CuratedEncoding(EncodingFamily.greek, 'windows-1253'),
  CuratedEncoding(EncodingFamily.turkish, 'windows-1254'),
  CuratedEncoding(EncodingFamily.hebrew, 'windows-1255'),
  CuratedEncoding(EncodingFamily.arabic, 'windows-1256'),
  CuratedEncoding(EncodingFamily.baltic, 'windows-1257'),
  CuratedEncoding(EncodingFamily.vietnamese, 'windows-1258'),
  CuratedEncoding(EncodingFamily.thai, 'TIS-620'),
  CuratedEncoding(EncodingFamily.chineseSimplified, 'GBK'),
  CuratedEncoding(EncodingFamily.chineseTraditional, 'Big5'),
  CuratedEncoding(EncodingFamily.japanese, 'Shift_JIS'),
  CuratedEncoding(EncodingFamily.korean, 'EUC-KR'),
];

const _aliases = <String, EncodingFamily>{
  'utf-8': EncodingFamily.unicode,
  'utf8': EncodingFamily.unicode,
  'utf-16': EncodingFamily.unicode,
  'utf-16le': EncodingFamily.unicode,
  'utf-16be': EncodingFamily.unicode,
  'windows-1252': EncodingFamily.western,
  'cp1252': EncodingFamily.western,
  'iso-8859-1': EncodingFamily.western,
  'iso-8859-15': EncodingFamily.western,
  'us-ascii': EncodingFamily.western,
  'windows-1250': EncodingFamily.central,
  'iso-8859-2': EncodingFamily.central,
  'windows-1251': EncodingFamily.cyrillic,
  'iso-8859-5': EncodingFamily.cyrillic,
  'koi8-r': EncodingFamily.cyrillic,
  'koi8-u': EncodingFamily.cyrillic,
  'ibm866': EncodingFamily.cyrillic,
  'windows-1253': EncodingFamily.greek,
  'iso-8859-7': EncodingFamily.greek,
  'windows-1254': EncodingFamily.turkish,
  'iso-8859-9': EncodingFamily.turkish,
  'windows-1255': EncodingFamily.hebrew,
  'iso-8859-8': EncodingFamily.hebrew,
  'iso-8859-8-i': EncodingFamily.hebrew,
  'windows-1256': EncodingFamily.arabic,
  'iso-8859-6': EncodingFamily.arabic,
  'windows-1257': EncodingFamily.baltic,
  'iso-8859-4': EncodingFamily.baltic,
  'iso-8859-13': EncodingFamily.baltic,
  'windows-1258': EncodingFamily.vietnamese,
  'tis-620': EncodingFamily.thai,
  'windows-874': EncodingFamily.thai,
  'x-windows-874': EncodingFamily.thai,
  'iso-8859-11': EncodingFamily.thai,
  'gbk': EncodingFamily.chineseSimplified,
  'gb18030': EncodingFamily.chineseSimplified,
  'gb2312': EncodingFamily.chineseSimplified,
  'big5': EncodingFamily.chineseTraditional,
  'big5-hkscs': EncodingFamily.chineseTraditional,
  'shift_jis': EncodingFamily.japanese,
  'windows-31j': EncodingFamily.japanese,
  'euc-jp': EncodingFamily.japanese,
  'iso-2022-jp': EncodingFamily.japanese,
  'euc-kr': EncodingFamily.korean,
  'iso-2022-kr': EncodingFamily.korean,
  'x-windows-949': EncodingFamily.korean,
};

/// The family a charset name belongs to, whatever spelling the detector or
/// the system used; null for one outside every family (shown raw).
EncodingFamily? familyOf(String? charset) =>
    charset == null ? null : _aliases[charset.toLowerCase()];

/// Whether two charset names are the same encoding for the picker's
/// checkmark (case differs between Java's canonical names and ours).
bool sameCharset(String? a, String? b) =>
    a != null && b != null && a.toLowerCase() == b.toLowerCase();

/// "Más…": every system charset not already in the short list, sorted.
List<String> extraEncodings(List<String> available) {
  final curated =
      curatedSubtitleEncodings.map((e) => e.charset.toLowerCase()).toSet();
  final out = available.where((c) => !curated.contains(c.toLowerCase())).toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return out;
}
