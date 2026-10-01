import 'generated/app_localizations.dart';

/// A duration the way a screen reader should say it ("1 hora 2 minutos"),
/// not the clock digits it is shown with: "12:34" is read as a time of day.
/// Past an hour the seconds are noise and are left out, unless
/// [withSeconds]: the seek bar steps by seconds, and a step that sounds the
/// same as where you were sounds like nothing happened.
String spokenDuration(
  AppLocalizations l,
  Duration d, {
  bool withSeconds = false,
}) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return [
    if (h > 0) l.a11yHours(h),
    if (m > 0) l.a11yMinutes(m),
    if ((h == 0 || withSeconds) && (s > 0 || (h == 0 && m == 0)))
      l.a11ySeconds(s),
  ].join(' ');
}
