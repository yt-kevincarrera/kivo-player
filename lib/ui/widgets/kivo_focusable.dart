import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens what a long press would (options, selection) from a keyboard or a
/// remote: the menu key, or a long-press-less "secondary" button.
class SecondaryActionIntent extends Intent {
  const SecondaryActionIntent();
}

/// Makes a gesture-only control (a GestureDetector tile, a chip) reachable
/// with a D-pad, a remote or a keyboard: it can take focus, Enter / OK /
/// Select activates it, the menu key runs [onSecondary], and while focused
/// it wears an accent ring.
///
/// The ring only shows in keyboard navigation (Flutter's focus-highlight
/// mode), so touch use looks exactly as before; the touch gestures stay with
/// the wrapped child.
class KivoFocusable extends StatefulWidget {
  final VoidCallback? onActivate;
  final VoidCallback? onSecondary;
  final FocusNode? focusNode;
  final BorderRadius borderRadius;
  final Widget child;

  const KivoFocusable({
    super.key,
    required this.onActivate,
    this.onSecondary,
    this.focusNode,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    required this.child,
  });

  @override
  State<KivoFocusable> createState() => _KivoFocusableState();
}

class _KivoFocusableState extends State<KivoFocusable> {
  bool _highlight = false;

  static const _shortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.contextMenu): SecondaryActionIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonX): SecondaryActionIntent(),
    SingleActivator(LogicalKeyboardKey.enter, shift: true):
        SecondaryActionIntent(),
  };

  @override
  Widget build(BuildContext context) {
    // The accent: Kivo's theme carries it as the secondary colour.
    final accent = Theme.of(context).colorScheme.secondary;
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      enabled: widget.onActivate != null,
      shortcuts: widget.onSecondary == null ? null : _shortcuts,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onActivate?.call()),
        if (widget.onSecondary != null)
          SecondaryActionIntent: CallbackAction<SecondaryActionIntent>(
              onInvoke: (_) => widget.onSecondary!()),
      },
      onShowFocusHighlight: (v) => setState(() => _highlight = v),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: _highlight
              ? Border.all(color: accent, width: 3)
              : const Border.fromBorderSide(BorderSide.none),
        ),
        child: widget.child,
      ),
    );
  }
}

/// A [GestureDetector] for taps that a D-pad or keyboard can also reach:
/// the same touch behaviour, plus focus, OK/Enter to tap, and the menu key
/// for [onSecondary]. A drop-in for the tap-only GestureDetectors of
/// Kivo's custom chips, segments and swatches.
class FocusableTap extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onLongPressUp;
  final VoidCallback? onLongPressCancel;
  final VoidCallback? onSecondary;
  final HitTestBehavior? behavior;
  final BorderRadius borderRadius;
  final Widget child;

  const FocusableTap({
    super.key,
    required this.onTap,
    this.onLongPress,
    this.onLongPressUp,
    this.onLongPressCancel,
    this.onSecondary,
    this.behavior,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    required this.child,
  });

  @override
  Widget build(BuildContext context) => KivoFocusable(
        onActivate: onTap,
        onSecondary: onSecondary,
        borderRadius: borderRadius,
        child: GestureDetector(
          behavior: behavior,
          onTap: onTap,
          onLongPress: onLongPress,
          onLongPressUp: onLongPressUp,
          onLongPressCancel: onLongPressCancel,
          child: child,
        ),
      );
}
