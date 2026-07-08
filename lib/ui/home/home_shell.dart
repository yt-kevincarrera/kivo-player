import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../mini_player/mini_player_bar.dart';
import '../settings/settings_screen.dart';
import 'library_screen.dart';
import 'state/library_selection.dart';
import 'widgets/selection_bottom_bar.dart';

/// App root: two bottom tabs (Videos / Ajustes), each with its own navigation
/// history (nested Navigator) so drilling into a folder or a settings section
/// keeps the tab bar. The full-screen player is pushed on the ROOT navigator
/// (see the `rootNavigator: true` pushes in the library/folder screens) so it
/// covers this bar during playback. The mini-player floats just above the bar.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  final _navKeys = [GlobalKey<NavigatorState>(), GlobalKey<NavigatorState>()];

  GlobalKey<NavigatorState> get _activeNav => _navKeys[_index];

  void _select(int i) {
    if (i == _index) {
      // Re-tapping the active tab pops it to its root (common tab convention).
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() => _index = i);
  }

  Widget _tab(int i, Widget root) => Navigator(
        key: _navKeys[i],
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => root),
      );

  @override
  Widget build(BuildContext context) {
    final selecting = ref.watch(librarySelectionProvider).isNotEmpty;
    return PopScope(
      // Back should first unwind the active tab's own stack; only when it can't
      // do we let the system handle it (leave the app).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // The system back gesture reaches THIS root PopScope before the nested
        // screens' PopScope, so selection-mode back must be handled here — else
        // the fallback below pops the root route (black screen) instead of just
        // clearing the selection.
        if (ref.read(librarySelectionProvider).isNotEmpty) {
          ref.read(librarySelectionProvider.notifier).clear();
          return;
        }
        final nav = _activeNav.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (_index != 0) {
          setState(() => _index = 0); // from a non-Videos tab, back returns to Videos
        } else {
          Navigator.of(context).pop(); // Videos tab root: leave the app
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  _tab(0, const LibraryScreen()),
                  _tab(1, const SettingsScreen()),
                ],
              ),
            ),
            if (!selecting) const MiniPlayerBar(),
          ],
        ),
        bottomNavigationBar: selecting
            ? const SelectionBottomBar()
            : _BottomTabBar(index: _index, onTap: _select),
      ),
    );
  }
}

class _BottomTabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomTabBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Row(
            children: [
              _item(cs, 0, Icons.play_circle_outline, 'Videos'),
              _item(cs, 1, Icons.settings_outlined, 'Ajustes'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(ColorScheme cs, int i, IconData icon, String label) {
    final active = i == index;
    final color = active ? cs.secondary : cs.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(i),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: color)),
          ],
        ),
      ),
    );
  }
}
