import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Vault multi-select: set of selected privatePaths. Mirrors
/// LibrarySelectionNotifier but is a separate provider so the two never
/// entangle.
class VaultSelectionNotifier extends StateNotifier<Set<String>> {
  VaultSelectionNotifier() : super(const {});

  bool isSelected(String path) => state.contains(path);
  bool get active => state.isNotEmpty;

  void toggle(String path) {
    final next = Set<String>.of(state);
    if (!next.remove(path)) next.add(path);
    state = next;
  }

  void toggleAll(Iterable<String> paths) {
    final group = paths.toSet();
    if (group.isEmpty) return;
    final next = Set<String>.of(state);
    if (group.every(next.contains)) {
      next.removeAll(group);
    } else {
      next.addAll(group);
    }
    state = next;
  }

  void selectAll(Iterable<String> paths) => state = paths.toSet();
  void clear() => state = const {};
}

final vaultSelectionProvider =
    StateNotifierProvider<VaultSelectionNotifier, Set<String>>(
        (ref) => VaultSelectionNotifier());
