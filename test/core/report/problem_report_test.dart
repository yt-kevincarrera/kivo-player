import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/errors/error_log.dart';
import 'package:kivo_player/core/report/problem_report.dart';

ErrorLogEntry _e(String code, String op, String detail, {String v = '1.20.0'}) =>
    ErrorLogEntry(
      code: code,
      op: op,
      timestampMs: DateTime(2026, 10, 1, 9, 5).millisecondsSinceEpoch,
      detail: detail,
      appVersion: v,
      androidSdk: 36,
    );

void main() {
  test('carries the version, device, description and every error', () {
    final r = buildProblemReport(
      appVersion: '1.20.0',
      androidSdk: 36,
      deviceModel: 'Google Pixel 6',
      locale: 'es',
      description: '  El video se queda en negro  ',
      entries: [
        _e('KV-601', 'updateCheck', 'API: HTTP 403'),
        _e('KV-504', 'decoderFallback', 'no frame after 3s', v: '1.19.0'),
      ],
    );
    expect(r, startsWith('Kivo 1.20.0\nAndroid SDK 36 · Google Pixel 6 · es'));
    expect(r, contains('El video se queda en negro'));
    expect(r, contains('2026-10-01 09:05  KV-601  updateCheck'));
    expect(r, contains('    API: HTTP 403'));
    expect(r, contains('KV-504  decoderFallback  (v1.19.0)'),
        reason: 'an entry from an older version says so');
  });

  test('no description, no errors: still a useful report', () {
    final r = buildProblemReport(
        appVersion: '1.20.0',
        androidSdk: 33,
        deviceModel: '',
        locale: 'en',
        entries: const []);
    expect(r, isNot(contains('What happened')));
    expect(r, contains('(none recorded)'));
    expect(r, contains('unknown device'));
  });

  test('the subject names the newest error', () {
    expect(problemReportSubject('1.20.0', [_e('KV-601', 'updateCheck', '')]),
        'Kivo 1.20.0 — KV-601');
    expect(problemReportSubject('1.20.0', const []),
        'Kivo 1.20.0 — problem report');
  });

  test('the cut is by encoded length: accented text cannot overflow the URL',
      () {
    final u = issueUrl('T', 'Información — línea\n' * 600);
    expect(Uri.encodeQueryComponent(u.queryParameters['body']!).length,
        lessThanOrEqualTo(6000));
    expect(u.toString().length, lessThan(8000));
  });

  test('the mailto link encodes spaces as %20, not +', () {
    final u = emailUrl('Kivo 1.20.0', 'a b\nc');
    expect(u.toString(),
        'mailto:kevin.ccdo@gmail.com?subject=Kivo%201.20.0&body=a%20b%0Ac');
  });

  test('the GitHub link prefills title and body, and cuts a long body', () {
    final u = issueUrl('T', 'x' * 7000);
    expect(u.queryParameters['title'], 'T');
    expect(Uri.encodeQueryComponent(u.queryParameters['body']!).length,
        lessThanOrEqualTo(6000));
    expect(u.queryParameters['body'], contains('send by email'));
  });
}
