import 'package:flutter/material.dart';

/// HSV picker (hue + saturation + value sliders, no external package/network).
/// Returns the chosen ARGB, or null on cancel.
Future<int?> showColorPickerSheet(BuildContext context, int initialArgb) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ColorPickerSheet(initial: Color(initialArgb)),
  );
}

class _ColorPickerSheet extends StatefulWidget {
  final Color initial;
  const _ColorPickerSheet({required this.initial});
  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv;
  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
  }

  Color get _color => _hsv.toColor();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Text('Personalizado',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface))),
            const SizedBox(height: 16),
            Container(height: 54, decoration: BoxDecoration(
                color: _color, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant))),
            const SizedBox(height: 14),
            _channel(context, 'Matiz', _hsv.hue, 360, (v) => setState(() => _hsv = _hsv.withHue(v))),
            _channel(context, 'Saturación', _hsv.saturation, 1, (v) => setState(() => _hsv = _hsv.withSaturation(v))),
            _channel(context, 'Brillo', _hsv.value, 1, (v) => setState(() => _hsv = _hsv.withValue(v))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: cs.secondary, foregroundColor: cs.onSecondary),
                onPressed: () => Navigator.of(context).pop(
                    _color.toARGB32() | 0xFF000000), // force opaque
                child: const Text('Aplicar'))),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _channel(BuildContext context, String name, double value, double max, ValueChanged<double> onChanged) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      SizedBox(width: 86, child: Text(name, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
      Expanded(child: Slider(value: value, min: 0, max: max, activeColor: cs.secondary, onChanged: onChanged)),
    ]);
  }
}
