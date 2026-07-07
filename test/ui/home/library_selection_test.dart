import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/ui/home/state/library_selection.dart';

void main() {
  test('toggle adds then removes; active tracks non-empty', () {
    final n = LibrarySelectionNotifier();
    expect(n.active, false);
    n.toggle('a');
    expect(n.state, {'a'});
    expect(n.active, true);
    expect(n.isSelected('a'), true);
    n.toggle('a');
    expect(n.state, isEmpty);
    expect(n.active, false);
  });

  test('toggleAll selects the whole group, then clears it when all present', () {
    final n = LibrarySelectionNotifier();
    n.toggle('a'); // partial
    n.toggleAll(['a', 'b', 'c']); // not all present → add the rest
    expect(n.state, {'a', 'b', 'c'});
    n.toggleAll(['a', 'b', 'c']); // all present → remove them
    expect(n.state, isEmpty);
  });

  test('selectAll replaces; clear empties', () {
    final n = LibrarySelectionNotifier();
    n.toggle('x');
    n.selectAll(['a', 'b']);
    expect(n.state, {'a', 'b'});
    n.clear();
    expect(n.state, isEmpty);
  });

  test('groupCheckState: none / some / all / empty', () {
    expect(groupCheckState(['a', 'b'], {}), GroupCheckState.none);
    expect(groupCheckState(['a', 'b'], {'a'}), GroupCheckState.some);
    expect(groupCheckState(['a', 'b'], {'a', 'b'}), GroupCheckState.all);
    expect(groupCheckState([], {'a'}), GroupCheckState.none);
  });
}
