import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/l10n.dart';
import 'tv_focusable.dart';
import 'tv_panel.dart';

class TvSettingValue extends StatelessWidget {
  const TvSettingValue({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.label,
    required this.onChanged,
  });
  final String title;
  final String? subtitle;
  final double value, min, max, step;
  final String Function(double) label;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => TvOptionRow(
    label: title,
    subtitle: subtitle,
    value: label(value),
    onPressed: () => showTvPanel<void>(
      context: context,
      title: title,
      builder: (_) => _ValueEditor(
        value: value,
        min: min,
        max: max,
        step: step,
        label: label,
        onChanged: onChanged,
      ),
    ),
  );
}

class _ValueEditor extends StatefulWidget {
  const _ValueEditor({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.label,
    required this.onChanged,
  });
  final double value, min, max, step;
  final String Function(double) label;
  final ValueChanged<double> onChanged;
  @override
  State<_ValueEditor> createState() => _ValueEditorState();
}

class _ValueEditorState extends State<_ValueEditor> {
  late double _value = widget.value;
  final _node = FocusNode(debugLabel: 'tv-setting-value');
  void _change(int direction) {
    final next = (_value + direction * widget.step)
        .clamp(widget.min, widget.max)
        .toDouble();
    if (next == _value) return;
    setState(() => _value = next);
    widget.onChanged(next);
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(7),
    children: [
      Text(
        context.l10n.tvAdjustValueHint,
        style: TextStyle(
          fontSize: 20,
          height: 1.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 32),
      Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          if (!_node.hasFocus ||
              (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _change(-1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _change(1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TvFocusable(
          label: widget.label(_value),
          value: widget.label(_value),
          focusNode: _node,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
            child: Row(
              children: [
                const Icon(Icons.chevron_left, size: 32),
                Expanded(
                  child: Text(
                    widget.label(_value),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 32),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
