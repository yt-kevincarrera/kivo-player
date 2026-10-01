part of 'track_picker.dart';

/// One captioned group of the Estilo tab: an eyebrow and a card holding the
/// related controls, so what belongs together reads together.
class _StyleGroup extends StatelessWidget {
  const _StyleGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionEyebrow(label: title),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 10, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF141C2E),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// A control's name inside a group.
class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

/// Small explanatory text at the end of a group.
class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 6, 2, 0),
        child: Text(
          text,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.42),
            fontSize: 11,
            height: 1.35,
          ),
        ),
      );
}

class _StyleSlider extends StatelessWidget {
  const _StyleSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.accent,
    required this.valueLabel,
    required this.onChanged,
    this.valueWidth = 84,
  });

  final double value, min, max;
  final int divisions;
  final Color accent;
  final String valueLabel;
  final double valueWidth;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.14),
              thumbColor: accent,
              overlayColor: accent.withValues(alpha: 0.15),
            ),
            child: Slider(
              min: min,
              max: max,
              divisions: divisions,
              value: value.clamp(min, max),
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: valueWidth,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// A labelled switch row, flat — it sits inside a group's card.
class _StyleSwitch extends StatelessWidget {
  const _StyleSwitch({
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? hint;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              if (hint != null)
                Text(hint!,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 11)),
            ],
          ),
        ),
        Switch(value: value, activeThumbColor: accent, onChanged: onChanged),
      ],
    );
  }
}

/// A font option, written in that font — the chip is its own sample.
class _FontChip extends StatelessWidget {
  const _FontChip({
    required this.label,
    required this.family,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String? family;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.16) : const Color(0xFF1E2840),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active ? accent.withValues(alpha: 0.6) : Colors.transparent),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: family,
            color: active ? accent : Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
