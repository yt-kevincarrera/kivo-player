import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Bespoke Kivo icon set. Each icon is a monochrome 24x24 SVG using
/// `currentColor`; [KivoIcon] tints the whole glyph via a colorFilter, so they
/// behave like normal tintable icons — the gold / white / disabled color is
/// decided by the call site (active = gold, idle = white, disabled = muted),
/// exactly like the Material icons they replace.
///
/// Style spec: 24x24 grid, 2px stroke, round caps/joins, hero glyphs (play,
/// seek arrows, volume speaker) filled; everything else line.
class KivoIcons {
  KivoIcons._();

  static const String _open = '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">';
  static const String _close = '</svg>';

  static String _wrap(String body) => '$_open$body$_close';

  // ---- transport ----
  static final String play = _wrap(
    '<path d="M8 6 L18 12 L8 18 Z" fill="currentColor" stroke="currentColor" stroke-width="2.4" stroke-linejoin="round"/>',
  );

  static final String pause = _wrap(
    '<g fill="currentColor"><rect x="6.5" y="5" width="3.6" height="14" rx="1.8"/>'
    '<rect x="13.9" y="5" width="3.6" height="14" rx="1.8"/></g>',
  );

  static final String fastForward = _wrap(
    '<g fill="currentColor" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round">'
    '<path d="M4 6.5 L11.5 12 L4 17.5 Z"/><path d="M12 6.5 L19.5 12 L12 17.5 Z"/></g>',
  );

  static final String fastRewind = _wrap(
    '<g fill="currentColor" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round">'
    '<path d="M20 6.5 L12.5 12 L20 17.5 Z"/><path d="M12 6.5 L4.5 12 L12 17.5 Z"/></g>',
  );

  // ---- skip N seconds (rotating arrow + number; caller draws the number? no — baked 10) ----
  static final String replay10 = _wrap(
    '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M5.2 8.5 A 7.2 7.2 0 1 0 8 5"/><path d="M8.4 2.2 L7.6 5.2 L10.6 5.9"/></g>'
    '<text x="12.2" y="15.4" text-anchor="middle" font-family="sans-serif" font-size="7.5" '
    'font-weight="700" fill="currentColor">10</text>',
  );

  static final String forward10 = _wrap(
    '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M18.8 8.5 A 7.2 7.2 0 1 1 16 5"/><path d="M15.6 2.2 L16.4 5.2 L13.4 5.9"/></g>'
    '<text x="11.8" y="15.4" text-anchor="middle" font-family="sans-serif" font-size="7.5" '
    'font-weight="700" fill="currentColor">10</text>',
  );

  // ---- top bar ----
  static final String back = _wrap(
    '<path d="M14 5.5 L7.5 12 L14 18.5 M7.5 12 H19.5" fill="none" stroke="currentColor" '
    'stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
  );

  static final String subtitles = _wrap(
    '<rect x="3.5" y="5.5" width="17" height="13" rx="3" fill="none" stroke="currentColor" stroke-width="2"/>'
    '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">'
    '<path d="M6.5 11 H10"/><path d="M12.5 11 H17.5"/><path d="M6.5 14.5 H13"/><path d="M15.5 14.5 H17.5"/></g>',
  );

  static final String pip = _wrap(
    '<rect x="3" y="5" width="18" height="14" rx="2.5" fill="none" stroke="currentColor" stroke-width="2"/>'
    '<rect x="11.5" y="11" width="7.5" height="6" rx="1.5" fill="currentColor"/>',
  );

  static final String audio = _wrap(
    '<path d="M5 14 V11.5 A7 7 0 0 1 19 11.5 V14" fill="none" stroke="currentColor" '
    'stroke-width="2" stroke-linecap="round"/>'
    '<rect x="3.5" y="13" width="4" height="6.5" rx="2" fill="currentColor"/>'
    '<rect x="16.5" y="13" width="4" height="6.5" rx="2" fill="currentColor"/>',
  );

  static final String more = _wrap(
    '<g fill="currentColor"><circle cx="12" cy="5.5" r="1.9"/><circle cx="12" cy="12" r="1.9"/>'
    '<circle cx="12" cy="18.5" r="1.9"/></g>',
  );

  /// Persistent info-overlay toggle (used in Plan 3).
  static final String info = _wrap(
    '<path d="M3 12 C6 7.5 9 5.5 12 5.5 C15 5.5 18 7.5 21 12 C18 16.5 15 18.5 12 18.5 '
    'C9 18.5 6 16.5 3 12 Z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/>'
    '<circle cx="12" cy="12" r="2.6" fill="currentColor"/>',
  );

  // ---- bottom bar / settings ----
  static final String lock = _wrap(
    '<rect x="5" y="10.5" width="14" height="9.5" rx="2.5" fill="none" stroke="currentColor" stroke-width="2"/>'
    '<path d="M8 10.5 V8 A4 4 0 0 1 16 8 V10.5" fill="none" stroke="currentColor" '
    'stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="15" r="1.4" fill="currentColor"/>',
  );

  static final String unlock = _wrap(
    '<rect x="5" y="10.5" width="14" height="9.5" rx="2.5" fill="none" stroke="currentColor" stroke-width="2"/>'
    '<path d="M8 10.5 V8 A4 4 0 0 1 15.5 6" fill="none" stroke="currentColor" '
    'stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="15" r="1.4" fill="currentColor"/>',
  );

  static final String aspect = _wrap(
    '<rect x="4" y="6" width="16" height="12" rx="2.5" fill="none" stroke="currentColor" stroke-width="2"/>'
    '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M7.5 9.5 V8 H9"/><path d="M16.5 14.5 V16 H15"/></g>',
  );

  static final String rotate = _wrap(
    '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M6 10 A7 7 0 0 1 18 7.5"/><path d="M18 4.5 L18.4 7.7 L15.2 8"/>'
    '<path d="M18 14 A7 7 0 0 1 6 16.5"/><path d="M6 19.5 L5.6 16.3 L8.8 16"/></g>',
  );

  static final String brightness = _wrap(
    '<circle cx="12" cy="12" r="4" fill="none" stroke="currentColor" stroke-width="2"/>'
    '<g stroke="currentColor" stroke-width="2" stroke-linecap="round">'
    '<path d="M12 2.5 V5"/><path d="M12 19 V21.5"/><path d="M2.5 12 H5"/><path d="M19 12 H21.5"/>'
    '<path d="M5.3 5.3 L7 7"/><path d="M17 17 L18.7 18.7"/><path d="M18.7 5.3 L17 7"/><path d="M7 17 L5.3 18.7"/></g>',
  );

  static final String volume = _wrap(
    '<path d="M4 9 H7 L11.5 5 V19 L7 15 H4 Z" fill="currentColor" stroke="currentColor" '
    'stroke-width="1.6" stroke-linejoin="round"/>'
    '<g fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">'
    '<path d="M14.5 9 A4 4 0 0 1 14.5 15"/><path d="M17 6.5 A8 8 0 0 1 17 17.5"/></g>',
  );

  static final String speed = _wrap(
    '<path d="M4 16.5 A9 9 0 0 1 20 16.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'
    '<path d="M12 16.5 L16.5 10" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'
    '<circle cx="12" cy="16.5" r="1.9" fill="currentColor"/>',
  );

  static final String plus = _wrap(
    '<path d="M12 6 V18 M6 12 H18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>',
  );

  static final String minus = _wrap(
    '<path d="M6 12 H18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/>',
  );

  static final String folderOpen = _wrap(
    '<path d="M3.5 18.5 V6.5 A1 1 0 0 1 4.5 5.5 H9 L11 7.5 H18.5 A1 1 0 0 1 19.5 8.5 V10 H7 Z" '
    'fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/>'
    '<path d="M3.5 18.5 L6.5 10 H22 L19 18.5 Z" fill="none" stroke="currentColor" '
    'stroke-width="2" stroke-linejoin="round"/>',
  );
}

/// Renders a [KivoIcons] SVG string, tinted like a normal icon.
class KivoIcon extends StatelessWidget {
  final String icon;
  final double size;
  final Color? color;

  const KivoIcon(this.icon, {super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? const Color(0xFFFFFFFF);
    return SvgPicture.string(
      icon,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
    );
  }
}
