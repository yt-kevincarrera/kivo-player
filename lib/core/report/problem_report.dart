import '../errors/error_log.dart';

/// Where problem reports go. The address the About screen already shows.
const problemReportEmail = 'kevin.ccdo@gmail.com';
const problemReportIssuesUrl =
    'https://github.com/yt-kevincarrera/kivo-player/issues/new';

/// The plain-text report a user sends by hand. Everything in it is shown to
/// them before it leaves the phone; nothing is sent automatically.
///
/// Written in English on purpose: it is read by the developer, not shown as
/// app UI, and the KV codes and technical details are language-neutral.
String buildProblemReport({
  required String appVersion,
  required int androidSdk,
  required String deviceModel,
  required String locale,
  required List<ErrorLogEntry> entries,
  String description = '',
  String recentOpens = '',
}) {
  final b = StringBuffer()
    ..writeln('Kivo $appVersion')
    ..writeln('Android SDK $androidSdk · ${deviceModel.isEmpty ? 'unknown device' : deviceModel} · $locale');
  final what = description.trim();
  if (what.isNotEmpty) {
    b
      ..writeln()
      ..writeln('— What happened —')
      ..writeln(what);
  }
  b
    ..writeln()
    ..writeln('— Recent errors (${entries.length}) —');
  if (entries.isEmpty) b.writeln('(none recorded)');
  for (final e in entries) {
    final at = DateTime.fromMillisecondsSinceEpoch(e.timestampMs);
    b.writeln('${_stamp(at)}  ${e.code}  ${e.op}'
        '${e.appVersion.isNotEmpty && e.appVersion != appVersion ? '  (v${e.appVersion})' : ''}');
    if (e.detail.isNotEmpty) b.writeln('    ${e.detail}');
  }
  if (recentOpens.isNotEmpty) {
    b
      ..writeln()
      ..writeln('— Recent video opens —')
      ..writeln(recentOpens);
  }
  return b.toString().trimRight();
}

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// A subject line that says which version and what the newest error was.
String problemReportSubject(String appVersion, List<ErrorLogEntry> entries) =>
    entries.isEmpty
        ? 'Kivo $appVersion — problem report'
        : 'Kivo $appVersion — ${entries.first.code}';

/// GitHub's new-issue URL with the report prefilled. Long reports are cut
/// (URLs past ~8 KB are refused); the email route has no such limit.
Uri issueUrl(String subject, String body) {
  // Measured encoded: Spanish text, dashes and line breaks grow 3–9× when
  // percent-encoded, so a character count lets the URL run past ~8 KB.
  const maxEncoded = 6000;
  const cutNote = '\n… (cut: send by email for the full report)';
  var b = body;
  if (Uri.encodeQueryComponent(b).length > maxEncoded) {
    var keep = b.length;
    while (keep > 0 &&
        Uri.encodeQueryComponent(b.substring(0, keep) + cutNote).length >
            maxEncoded) {
      keep = (keep * 0.9).floor();
    }
    b = b.substring(0, keep) + cutNote;
  }
  return Uri.parse(problemReportIssuesUrl)
      .replace(queryParameters: {'title': subject, 'body': b});
}

/// A `mailto:` link to [problemReportEmail] with the report as its body.
Uri emailUrl(String subject, String body) => Uri(
      scheme: 'mailto',
      path: problemReportEmail,
      // Uri's own encoder writes spaces as '+', which mail apps show
      // literally; encodeComponent gives %20.
      query: 'subject=${Uri.encodeComponent(subject)}'
          '&body=${Uri.encodeComponent(body)}',
    );
