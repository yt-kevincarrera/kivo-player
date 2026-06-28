int naturalCompare(String a, String b) {
  final ra = _tokenize(a.toLowerCase());
  final rb = _tokenize(b.toLowerCase());
  final n = ra.length < rb.length ? ra.length : rb.length;
  for (var i = 0; i < n; i++) {
    final ta = ra[i], tb = rb[i];
    final na = int.tryParse(ta), nb = int.tryParse(tb);
    int c;
    if (na != null && nb != null) {
      c = na.compareTo(nb);
    } else {
      c = ta.compareTo(tb);
    }
    if (c != 0) return c;
  }
  int c = ra.length.compareTo(rb.length);
  if (c != 0) return c;
  // Tiebreaker: case-sensitive comparison of original strings
  return a.compareTo(b);
}

List<String> _tokenize(String s) {
  final out = <String>[];
  final buf = StringBuffer();
  bool? digit;
  for (final ch in s.codeUnits) {
    final isDigit = ch >= 0x30 && ch <= 0x39;
    if (digit != null && isDigit != digit && buf.isNotEmpty) {
      out.add(buf.toString());
      buf.clear();
    }
    buf.writeCharCode(ch);
    digit = isDigit;
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}
