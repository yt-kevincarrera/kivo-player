import 'package:flutter/material.dart';

/// Rounded card that groups setting rows with hairline dividers between them.
class SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const SettingsCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(height: 1, thickness: 1, color: cs.outlineVariant.withValues(alpha: 0.5)));
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(13),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

class SettingNavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const SettingNavRow({super.key, required this.icon, required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: cs.secondary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: cs.secondary),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class SettingSwitch extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SettingSwitch({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 6, 10, 6),
      child: Row(
        children: [
          Expanded(child: _titleBlock(context, title, subtitle)),
          Switch(value: value, activeThumbColor: cs.secondary, onChanged: onChanged),
        ],
      ),
    );
  }
}

class SettingSlider extends StatelessWidget {
  final String title;
  final double value, min, max;
  final int? divisions;
  final String Function(double) label;
  final ValueChanged<double> onChanged;
  const SettingSlider({super.key, required this.title, required this.value, required this.min,
      required this.max, this.divisions, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface))),
            Text(label(value), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700,
                color: cs.secondary, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(overlayShape: SliderComponentShape.noOverlay),
            child: Slider(
              value: value.clamp(min, max), min: min, max: max, divisions: divisions,
              activeColor: cs.secondary, inactiveColor: cs.onSurfaceVariant.withValues(alpha: 0.3),
              onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

class SettingStepper extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int value, min, max, step;
  final String Function(int) label;
  final ValueChanged<int> onChanged;
  const SettingStepper({super.key, required this.title, this.subtitle, required this.value,
      required this.min, required this.max, this.step = 1, required this.label, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canDown = value - step >= min;
    final canUp = value + step <= max;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 8, 12, 8),
      child: Row(
        children: [
          Expanded(child: _titleBlock(context, title, subtitle)),
          Container(
            decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(9)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _stepBtn(context, '−', canDown ? () => onChanged(value - step) : null),
              SizedBox(
                width: 44,
                child: Text(label(value), textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cs.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              _stepBtn(context, '+', canUp ? () => onChanged(value + step) : null),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(BuildContext context, String glyph, VoidCallback? onTap) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 34, height: 32,
        child: Center(child: Text(glyph, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
            color: onTap == null ? cs.onSurfaceVariant.withValues(alpha: 0.35) : cs.secondary))),
      ),
    );
  }
}

class SettingSegmented<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const SettingSegmented({super.key, required this.title, this.subtitle,
      required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 11, 15, 11),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _titleBlock(context, title, subtitle),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              for (final (v, lbl) in options)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(v),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: v == value ? cs.secondary : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(lbl, textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                              color: v == value ? cs.onSecondary : cs.onSurfaceVariant)),
                    ),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

Widget _titleBlock(BuildContext context, String title, String? subtitle) {
  final cs = Theme.of(context).colorScheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
      if (subtitle != null)
        Padding(
          padding: const EdgeInsets.only(top: 3, right: 8),
          child: Text(subtitle, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant, height: 1.35)),
        ),
    ],
  );
}
