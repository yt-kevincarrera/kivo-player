import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tv_input_mode.dart';

class _TvSecondaryIntent extends Intent {
  const _TvSecondaryIntent();
}

/// A TV control has one focus target and one spoken label. Focus is visible
/// from the first frame, including remotes reported as touch/pointer devices.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.label,
    required this.onPressed,
    required this.child,
    this.autofocus = false,
    this.onFocus,
    this.focusNode,
    this.selected,
    this.scale = 1,
    this.onSecondary,
    this.toggled,
    this.value,
  });
  final String label;
  final VoidCallback? onPressed;
  final Widget child;
  final bool autofocus;
  final bool? selected;
  final bool? toggled;
  final String? value;
  final double scale;
  final ValueChanged<bool>? onFocus;
  final VoidCallback? onSecondary;
  final FocusNode? focusNode;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;
  late final _internalNode = FocusNode(debugLabel: widget.label);
  FocusNode get _node => widget.focusNode ?? _internalNode;
  void _activate() {
    if (widget.onPressed == null) return;
    _node.requestFocus();
    // Pointer-shaped TV remotes and accessibility activation must establish
    // the same return target as a D-pad press before a modal captures it.
    FocusManager.instance.applyFocusChangesIfNeeded();
    widget.onPressed!();
  }

  @override
  void dispose() {
    _internalNode.dispose();
    super.dispose();
  }

  void _focus(bool value) {
    setState(() => _focused = value);
    widget.onFocus?.call(value);
    if (value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final accent = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      label: widget.label,
      selected: widget.selected,
      toggled: widget.toggled,
      value: widget.value,
      enabled: widget.onPressed != null,
      focused: _focused,
      onTap: widget.onPressed == null ? null : _activate,
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        focusNode: _node,
        enabled: widget.onPressed != null,
        onFocusChange: _focus,
        shortcuts: const {
          ...TvRemoteShortcuts.bindings,
          SingleActivator(
            LogicalKeyboardKey.contextMenu,
            includeRepeats: false,
          ): _TvSecondaryIntent(),
          SingleActivator(LogicalKeyboardKey.contextMenu):
              TvIgnoreRepeatIntent(),
        },
        actions: {
          TvIgnoreRepeatIntent: CallbackAction<TvIgnoreRepeatIntent>(
            onInvoke: (_) => null,
          ),
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
          if (widget.onSecondary != null)
            _TvSecondaryIntent: CallbackAction<_TvSecondaryIntent>(
              onInvoke: (_) {
                widget.onSecondary!();
                return null;
              },
            ),
        },
        child: MouseRegion(
          cursor: widget.onPressed == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onPressed == null ? null : _activate,
            child: AnimatedScale(
              scale: _focused && !reduce ? widget.scale : 1,
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              child: AnimatedContainer(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _focused
                      ? [
                          BoxShadow(color: accent, spreadRadius: 5),
                          const BoxShadow(color: Colors.black, spreadRadius: 3),
                        ]
                      : const [],
                ),
                child: ExcludeSemantics(child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.autofocus = false,
    this.focusNode,
    this.selected,
    this.onFocus,
    this.trailing,
    this.subtitle,
    this.toggled,
    this.value,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final bool autofocus;
  final bool? selected;
  final bool? toggled;
  final String? value;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocus;
  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TvFocusable(
      label: [label, if (subtitle != null) subtitle!].join('. '),
      onPressed: onPressed,
      autofocus: autofocus,
      selected: selected,
      toggled: toggled,
      value: value,
      focusNode: focusNode,
      onFocus: onFocus,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: primary
              ? colors.onSurface
              : selected == true
              ? colors.onSurface.withValues(alpha: .07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 24,
                color: primary ? colors.surface : colors.onSurface,
              ),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: primary ? colors.surface : colors.onSurface,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 16,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 24), trailing!],
          ],
        ),
      ),
    );
  }
}
