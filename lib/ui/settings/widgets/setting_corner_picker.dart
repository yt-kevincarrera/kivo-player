import 'package:flutter/material.dart';

/// Picks one of the four corners ('tl'/'tr'/'bl'/'br') on a mini rectangle.
class SettingCornerPicker extends StatelessWidget {
  final String title;
  final String value;
  final ValueChanged<String> onChanged;
  const SettingCornerPicker({super.key, required this.title, required this.value, required this.onChanged});

  static const _corners = <(String, Alignment)>[
    ('tl', Alignment.topLeft), ('tr', Alignment.topRight),
    ('bl', Alignment.bottomLeft), ('br', Alignment.bottomRight),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
      child: Row(children: [
        Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface))),
        Container(
          width: 110, height: 64,
          decoration: BoxDecoration(
            color: cs.surface, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Stack(children: [
            for (final (code, align) in _corners)
              Align(
                alignment: align,
                child: GestureDetector(
                  key: ValueKey('corner-$code'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(code),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Container(
                      width: 20, height: 13,
                      decoration: BoxDecoration(
                        color: code == value ? cs.secondary : Colors.transparent,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: code == value ? cs.secondary : cs.onSurfaceVariant.withValues(alpha: 0.6)),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
