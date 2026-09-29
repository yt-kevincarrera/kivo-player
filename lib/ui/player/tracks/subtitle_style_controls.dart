part of 'track_picker.dart';

/// The Estilo tab's controls beyond size and colours: outline, font, shadow,
/// bold, position, and how ASS files are drawn. Every change lands in the
/// settings, which Kivo's overlay (and the preview above) read directly.
class _StyleExtras extends ConsumerWidget {
  const _StyleExtras();

  static const _outlineSwatches = [
    0xFF000000,
    0xFFFFFFFF,
    0xFF3A3A3A,
    0xFF1B2A4A,
  ];

  void _set(WidgetRef ref, KivoSettings Function(KivoSettings) f) {
    ref.read(settingsProvider.notifier).set(f(ref.read(settingsProvider)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final accent = Color(s.accentColor);
    final l10n = context.l10n;
    final fonts = [
      ('default', l10n.playerTracksFontDefault),
      ('serif', l10n.playerTracksFontSerif),
      ('mono', l10n.playerTracksFontMono),
      ('condensed', l10n.playerTracksFontCondensed),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionEyebrow(label: l10n.playerTracksOutlineLabel),
        _StyleSlider(
          value: s.subtitleOutlineWidth,
          min: 0,
          max: 5,
          divisions: 10,
          accent: accent,
          valueLabel: s.subtitleOutlineWidth == 0
              ? l10n.playerTracksOutlineNone
              : s.subtitleOutlineWidth.toStringAsFixed(1),
          onChanged: (v) => _set(ref, (x) => x.copyWith(subtitleOutlineWidth: v)),
        ),
        if (s.subtitleOutlineWidth > 0) ...[
          _SectionEyebrow(label: l10n.playerTracksOutlineColorLabel),
          Row(
            children: [
              for (final c in _outlineSwatches)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _ColorSquare(
                    color: c,
                    active: s.subtitleOutlineColor == c,
                    accent: accent,
                    onTap: () =>
                        _set(ref, (x) => x.copyWith(subtitleOutlineColor: c)),
                  ),
                ),
            ],
          ),
        ],
        _SectionEyebrow(label: l10n.playerTracksFontLabel),
        Row(
          children: [
            for (final (id, label) in fonts)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _FontChip(
                    label: label,
                    family: subtitleFontFamily(id),
                    active: s.subtitleFontFamily == id,
                    accent: accent,
                    onTap: () =>
                        _set(ref, (x) => x.copyWith(subtitleFontFamily: id)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _StyleSwitch(
          label: l10n.playerTracksShadowLabel,
          value: s.subtitleShadow,
          accent: accent,
          onChanged: (v) => _set(ref, (x) => x.copyWith(subtitleShadow: v)),
        ),
        _StyleSwitch(
          label: l10n.playerTracksBoldLabel,
          value: s.subtitleBold,
          accent: accent,
          onChanged: (v) => _set(ref, (x) => x.copyWith(subtitleBold: v)),
        ),
        _SectionEyebrow(label: l10n.playerTracksPositionLabel),
        _StyleSlider(
          value: s.subtitleBottomMargin,
          min: 0,
          max: 40,
          divisions: 40,
          accent: accent,
          valueLabel:
              l10n.playerTracksPositionValue(s.subtitleBottomMargin.round()),
          onChanged: (v) => _set(ref, (x) => x.copyWith(subtitleBottomMargin: v)),
        ),
        _SectionEyebrow(label: l10n.playerTracksSecondaryPositionLabel),
        _StyleSlider(
          value: s.secondarySubtitleTopMargin,
          min: 0,
          max: 40,
          divisions: 40,
          accent: accent,
          valueLabel: l10n
              .playerTracksPositionValue(s.secondarySubtitleTopMargin.round()),
          onChanged: (v) =>
              _set(ref, (x) => x.copyWith(secondarySubtitleTopMargin: v)),
        ),
        const SizedBox(height: 6),
        _StyleSwitch(
          label: l10n.playerTracksRespectAss,
          hint: l10n.playerTracksRespectAssHint,
          value: s.subtitleRespectAss,
          accent: accent,
          onChanged: (v) => _set(ref, (x) => x.copyWith(subtitleRespectAss: v)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
          child: Text(
            l10n.playerTracksPictureSubsNote,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
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
  });

  final double value, min, max;
  final int divisions;
  final Color accent;
  final String valueLabel;
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
          width: 84,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
        decoration: BoxDecoration(
          color: const Color(0xFF182036),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
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
        ),
      ),
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
          color: active ? accent.withValues(alpha: 0.16) : const Color(0xFF182036),
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
