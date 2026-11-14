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
      onTap: widget.onPressed,
      child: FocusableActionDetector(
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
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
              widget.onPressed?.call();
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
            onTap: widget.onPressed,
            child: AnimatedScale(
              scale: _focused && !reduce ? widget.scale : 1,
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              child: AnimatedContainer(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 120),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _focused ? accent : Colors.transparent,
                    width: 3,
                  ),
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
              ? colors.primary
              : selected == true
              ? colors.primary.withValues(alpha: .14)
              : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 24,
                color: primary ? colors.onPrimary : colors.onSurface,
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
                      color: primary ? colors.onPrimary : colors.onSurface,
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
