import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/update/release_notes.dart';

void main() {
  test('a body that is only the compare link becomes nothing', () {
    // Every release before the workflow was fixed looks exactly like this.
    const body =
        '**Full Changelog**: https://github.com/yt-kevincarrera/kivo-player/compare/v1.8.1...v1.9.0';
    expect(cleanReleaseNotes(body), '');
  });

  test('the compare link is dropped but the changes are kept', () {
    const body = '''
## Novedades

- lista de capítulos
- captura de fotograma

**Full Changelog**: https://github.com/a/b/compare/v1...v2''';
    expect(cleanReleaseNotes(body), '- lista de capítulos\n- captura de fotograma');
  });

  test('GitHub headings go, since the dialog already has a title', () {
    const body = "## What's Changed\n- algo\n## Novedades\n- otra cosa";
    expect(cleanReleaseNotes(body), '- algo\n- otra cosa');
  });

  test('a bare link on its own line goes too', () {
    const body = '- algo\nhttps://github.com/a/b/releases/tag/v2';
    expect(cleanReleaseNotes(body), '- algo');
  });

  test('a link inside a sentence is left alone', () {
    // Dropping the whole line would lose the sentence with it.
    const body = '- mira https://ejemplo.com para más detalles';
    expect(cleanReleaseNotes(body), '- mira https://ejemplo.com para más detalles');
  });

  test('blank runs are collapsed so the dialog does not show gaps', () {
    const body = '- uno\n\n\n\n- dos';
    expect(cleanReleaseNotes(body), '- uno\n\n- dos');
  });

  test('an empty body stays empty', () {
    expect(cleanReleaseNotes(''), '');
    expect(cleanReleaseNotes('   \n\n  '), '');
  });
}
