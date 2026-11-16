import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../../player/control/gesture_math.dart';
import '../../widgets/kivo_focusable.dart';
import '../../tv/tv_input_mode.dart';
import '../../tv/tv_panel.dart';
import '../../tv/tv_focusable.dart';
import '../../tv/tv_setting_value.dart';

/// Edits a list of playback speeds as removable chips plus an "add" sheet.
/// Used for both the speed presets and the hold-right detents.
class SettingSpeedList extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<double> values;
  final double min;
  final double max;
  final ValueChanged<List<double>> onChanged;
  const SettingSpeedList({
    super.key,
    required this.title,
    this.subtitle,
    required this.values,
    this.min = 0.25,
    this.max = 8.0,
    required this.onChanged,
  });

  static String fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  Widget build(BuildContext context) {
    if (TvInputMode.of(context)) {
      return TvOptionRow(
        label: title,
        subtitle: subtitle,
        value: values.map((v) => '${fmt(v)}x').join(', '),
        onPressed: () => showTvPanel<void>(
          context: context,
          title: title,
          builder: (_) => _TvSpeedEditor(
            values: values,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final sorted = [...values]..sort();
    final canRemove = sorted.length > 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                subtitle!,
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in sorted) _chip(context, cs, v, canRemove),
              _addChip(context, cs),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, ColorScheme cs, double v, bool canRemove) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 7, canRemove ? 6 : 12, 7),
      decoration: BoxDecoration(
        color: cs.secondary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.secondary.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${fmt(v)}×',
            style: TextStyle(
              color: cs.secondary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          if (canRemove) ...[
            const SizedBox(width: 3),
            FocusableTap(
              onTap: () => onChanged([...values]..remove(v)),
              child: Icon(Icons.close, size: 15, color: cs.secondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _addChip(BuildContext context, ColorScheme cs) {
    return FocusableTap(
      key: const ValueKey('speed-add'),
      onTap: () async {
        final added = await showModalBottomSheet<double>(
          context: context,
          isScrollControlled: true,
          backgroundColor: cs.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => _AddSpeedSheet(min: min, max: max),
        );
        if (added != null) {
          final next = ({...values, round2(added)}.toList())..sort();
          onChanged(next);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
        ),
        child: Icon(Icons.add, size: 18, color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _AddSpeedSheet extends StatefulWidget {
  final double min, max;
  const _AddSpeedSheet({required this.min, required this.max});
  @override
  State<_AddSpeedSheet> createState() => _AddSpeedSheetState();
}

class _AddSpeedSheetState extends State<_AddSpeedSheet> {
  late double _v = widget.min;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final divisions = ((widget.max - widget.min) / 0.25).round();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                context.l10n.settingsSpeedAddDialogTitle,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                '${SettingSpeedList.fmt(_v)}×',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: cs.secondary,
                ),
              ),
            ),
            Slider(
              value: _v,
              min: widget.min,
              max: widget.max,
              divisions: divisions,
              activeColor: cs.secondary,
              onChanged: (x) => setState(() => _v = round2(x)),
            ),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.l10n.commonCancel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.secondary,
                      foregroundColor: cs.onSecondary,
                    ),
                    onPressed: () => Navigator.of(context).pop(_v),
                    child: Text(context.l10n.settingsSpeedAddAction),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TvSpeedEditor extends StatefulWidget {
  const _TvSpeedEditor({
    required this.values,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final List<double> values;
  final double min, max;
  final ValueChanged<List<double>> onChanged;
  @override
  State<_TvSpeedEditor> createState() => _TvSpeedEditorState();
}

class _TvSpeedEditorState extends State<_TvSpeedEditor> {
  late List<double> _values = [...widget.values]..sort();
  late double _newValue = widget.min;
  void _save(List<double> next) {
    setState(() => _values = next..sort());
    widget.onChanged(_values);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(6),
    children: [
      for (final v in _values)
        TvOptionRow(
          label: '${SettingSpeedList.fmt(v)}x',
          icon: Icons.remove_circle_outline,
          onPressed: _values.length > 1
              ? () => _save([..._values]..remove(v))
              : null,
        ),
      const SizedBox(height: 20),
      TvSettingValue(
        title: context.l10n.settingsSpeedAddDialogTitle,
        value: _newValue,
        min: widget.min,
        max: widget.max,
        step: .25,
        label: (v) => '${SettingSpeedList.fmt(v)}x',
        onChanged: (v) => setState(() => _newValue = round2(v)),
      ),
      TvButton(
        label: context.l10n.settingsSpeedAddDialogTitle,
        icon: Icons.add,
        onPressed: () => _save({..._values, _newValue}.toList()),
      ),
    ],
  );
}
