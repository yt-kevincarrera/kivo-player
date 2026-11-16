import 'package:flutter/material.dart';
import '../../tv/tv_input_mode.dart';
import '../../tv/tv_panel.dart';

/// A titled radio-style list: one selectable row per option.
class SettingChoice<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const SettingChoice({
    super.key,
    required this.title,
    this.subtitle,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (TvInputMode.of(context)) {
      return TvOptionRow(
        label: title,
        subtitle: subtitle,
        value: options.where((o) => o.$1 == value).map((o) => o.$2).firstOrNull,
        onPressed: () => showTvPanel<void>(
          context: context,
          title: title,
          builder: (ctx) => ListView(
            padding: const EdgeInsets.all(6),
            children: [
              for (var i = 0; i < options.length; i++)
                TvOptionRow(
                  label: options[i].$2,
                  selected: options[i].$1 == value,
                  autofocus: options.any((o) => o.$1 == value)
                      ? options[i].$1 == value
                      : i == 0,
                  onPressed: () {
                    onChanged(options[i].$1);
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
          ),
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 6),
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
          const SizedBox(height: 4),
          for (final (v, lbl) in options)
            InkWell(
              onTap: () => onChanged(v),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    Icon(
                      v == value
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 20,
                      color: v == value ? cs.secondary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        lbl,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: v == value
                              ? cs.onSurface
                              : cs.onSurfaceVariant,
                          fontWeight: v == value
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
