import 'package:flutter/material.dart';

/// A titled radio-style list: one selectable row per option.
class SettingChoice<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const SettingChoice({super.key, required this.title, this.subtitle,
      required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
          if (subtitle != null)
            Padding(padding: const EdgeInsets.only(top: 3),
              child: Text(subtitle!, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant))),
          const SizedBox(height: 4),
          for (final (v, lbl) in options)
            InkWell(
              onTap: () => onChanged(v),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(children: [
                  Icon(v == value ? Icons.radio_button_checked : Icons.radio_button_off,
                      size: 20, color: v == value ? cs.secondary : cs.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(child: Text(lbl, style: TextStyle(fontSize: 13.5,
                      color: v == value ? cs.onSurface : cs.onSurfaceVariant,
                      fontWeight: v == value ? FontWeight.w600 : FontWeight.w500))),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
