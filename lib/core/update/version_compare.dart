/// Compares two semver-ish strings. Returns >0 if [a] is newer than [b], 0 if
/// equal, <0 if older. Tolerant: strips a leading `v`, ignores anything from a
/// `+` or `-` onward (build/pre-release), missing segments count as 0, and
/// non-numeric segments degrade to 0 (never throws).
int compareVersions(String a, String b) {
  final pa = _parse(a);
  final pb = _parse(b);
  for (var i = 0; i < 3; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return 0;
}

bool isNewer(String candidate, String current) =>
    compareVersions(candidate, current) > 0;

List<int> _parse(String v) {
  var s = v.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  // Drop build (+...) and pre-release (-...) suffixes.
  final plus = s.indexOf('+');
  if (plus >= 0) s = s.substring(0, plus);
  final dash = s.indexOf('-');
  if (dash >= 0) s = s.substring(0, dash);
  final parts = s.split('.');
  final out = <int>[0, 0, 0];
  for (var i = 0; i < 3 && i < parts.length; i++) {
    out[i] = int.tryParse(parts[i].trim()) ?? 0;
  }
  return out;
}
