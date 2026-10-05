import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/diagnostics/open_trace.dart';

void main() {
  setUp(() => OpenTrace.instance.clear());

  test('an open and its steps, in the report', () async {
    final t = OpenTrace.instance;
    t.begin('the library');
    t.mark('player: screen created');
    await t.timed('set hwdec=auto-safe', () async {});
    final r = t.report();
    expect(r, contains('open from the library'));
    expect(r, contains('player: screen created'));
    expect(r, matches(RegExp(r'set hwdec=auto-safe \d+us')));
  });

  test('nothing recorded before any open; only the last 4 kept', () async {
    final t = OpenTrace.instance;
    t.mark('ignored');
    expect(t.report(), contains('no video opened'));
    for (var i = 0; i < 6; i++) {
      t.begin('open $i');
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    final r = t.report();
    expect(r, isNot(contains('open 1')));
    expect(r, contains('open 2'));
    expect(r, contains('open 5'));
  });

  // The library open goes through the plain one: one open, its own name.
  test('two begins back to back are one open, the first name kept', () {
    final t = OpenTrace.instance;
    t.begin('the library');
    t.begin('a file');
    final r = t.report();
    expect(r, contains('open from the library'));
    expect(r, isNot(contains('open from a file')));
  });
}
