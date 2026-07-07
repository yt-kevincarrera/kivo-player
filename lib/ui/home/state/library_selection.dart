import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Library multi-select: the set of selected video URIs. Selection mode is
/// active ⇔ the set is non-empty (deselecting the last item exits the mode).
class LibrarySelectionNotifier extends StateNotifier<Set<String>> {
  LibrarySelectionNotifier() : super(const {});

  bool isSelected(String uri) => state.contains(uri);
  bool get active => state.isNotEmpty;

  void toggle(String uri) {
    final next = Set<String>.of(state);
    if (!next.remove(uri)) next.add(uri);
    state = next;
  }

  /// Toggle a whole group (a day): remove them all if every one is already
  /// selected, otherwise add the missing ones.
  void toggleAll(Iterable<String> uris) {
    final group = uris.toSet();
    if (group.isEmpty) return;
    final next = Set<String>.of(state);
    if (group.every(next.contains)) {
      next.removeAll(group);
    } else {
      next.addAll(group);
    }
    state = next;
  }

  /// Select exactly [uris] (for "select all" with the visible list).
  void selectAll(Iterable<String> uris) => state = uris.toSet();

  void clear() => state = const {};
}

final librarySelectionProvider =
    StateNotifierProvider<LibrarySelectionNotifier, Set<String>>(
      (ref) => LibrarySelectionNotifier(),
    );

enum GroupCheckState { none, some, all }

/// Tri-state for a day header's checkbox given the group's URIs and the
/// current selection.
GroupCheckState groupCheckState(
  Iterable<String> groupUris,
  Set<String> selected,
) {
  final group = groupUris.toSet();
  if (group.isEmpty) return GroupCheckState.none;
  final n = group.where(selected.contains).length;
  if (n == 0) return GroupCheckState.none;
  if (n == group.length) return GroupCheckState.all;
  return GroupCheckState.some;
}
