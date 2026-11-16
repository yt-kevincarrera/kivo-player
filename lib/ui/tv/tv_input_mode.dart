import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

class TvIgnoreRepeatIntent extends Intent {
  const TvIgnoreRepeatIntent();
}

/// Repeated OK must not open several routes or toggle a switch repeatedly.
/// Matching repeat events to a consuming action also prevents Flutter's outer
/// default shortcuts from activating the focused control a second time.
class TvRemoteShortcuts extends StatelessWidget {
  const TvRemoteShortcuts({super.key, required this.child});
  final Widget child;
  static const bindings = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.select, includeRepeats: false):
        ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
        ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter, includeRepeats: false):
        ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonA, includeRepeats: false):
        ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.select): TvIgnoreRepeatIntent(),
    SingleActivator(LogicalKeyboardKey.enter): TvIgnoreRepeatIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): TvIgnoreRepeatIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonA): TvIgnoreRepeatIntent(),
  };
  static const keyboardBindings = <ShortcutActivator, Intent>{
    ...bindings,
    SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
        ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): TvIgnoreRepeatIntent(),
  };
  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      TvIgnoreRepeatIntent: CallbackAction<TvIgnoreRepeatIntent>(
        onInvoke: (_) => null,
      ),
    },
    child: Shortcuts(shortcuts: keyboardBindings, child: child),
  );
}

class TvInputMode extends InheritedWidget {
  const TvInputMode({super.key, required this.enabled, required super.child});
  final bool enabled;
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvInputMode>()?.enabled ??
      false;
  @override
  bool updateShouldNotify(TvInputMode oldWidget) =>
      enabled != oldWidget.enabled;
}
