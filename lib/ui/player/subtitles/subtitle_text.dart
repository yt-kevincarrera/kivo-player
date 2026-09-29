import 'package:flutter/material.dart';

import '../../../core/settings/kivo_settings.dart';

/// Android's own font families: each keeps the system's per-script fallback,
/// which is the whole reason Kivo draws text subtitles itself.
String? subtitleFontFamily(String id) => switch (id) {
      'serif' => 'serif',
      'mono' => 'monospace',
      'condensed' => 'sans-serif-condensed',
      _ => null,
    };

/// The size settings are expressed at a 360 dp short side; this scales them
/// to the space actually available.
double subtitleScaleFor(Size size) =>
    (size.shortestSide / 360).clamp(0.5, 3.0);

/// One subtitle, in the user's style. The same widget draws the live overlay
/// and the Estilo preview, so what the preview shows is what the video shows.
class SubtitleText extends StatelessWidget {
  const SubtitleText({
    super.key,
    required this.text,
    required this.settings,
    this.scale = 1.0,
  });

  final String text;
  final KivoSettings settings;

  /// Multiplies every size (font, outline, shadow, padding).
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final base = TextStyle(
      fontSize: s.subtitleFontSize * scale,
      fontFamily: subtitleFontFamily(s.subtitleFontFamily),
      fontWeight: s.subtitleBold ? FontWeight.w800 : FontWeight.w600,
      height: 1.25,
      color: Color(s.subtitleTextColor),
      shadows: s.subtitleShadow
          ? [
              Shadow(
                color: const Color(0xCC000000),
                offset: Offset(1.2 * scale, 1.6 * scale),
                blurRadius: 3 * scale,
              ),
            ]
          : null,
    );
    final outline = s.subtitleOutlineWidth * scale;

    final Widget glyphs = outline <= 0
        ? Text(text, textAlign: TextAlign.center, style: base)
        : Stack(
            alignment: Alignment.center,
            children: [
              // The stroke is centred on the glyph edge, so twice the width
              // shows [outline] outside it; the fill drawn on top hides the
              // inner half. Excluded from semantics: a screen reader must read
              // each line once, not once per layer.
              ExcludeSemantics(child: Text(
                text,
                textAlign: TextAlign.center,
                style: base.copyWith(
                  color: null,
                  shadows: s.subtitleShadow ? base.shadows : null,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = outline * 2
                    ..strokeJoin = StrokeJoin.round
                    ..color = Color(s.subtitleOutlineColor),
                ),
              )),
              Text(text,
                  textAlign: TextAlign.center,
                  style: base.copyWith(shadows: null)),
            ],
          );

    final bg = Color(s.subtitleBackgroundColor);
    if (bg.a == 0) return glyphs;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5 * scale),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 10 * scale, vertical: 3 * scale),
        child: glyphs,
      ),
    );
  }
}
