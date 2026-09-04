import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/l10n.dart';
import '../../../platform/pip_controller_provider.dart';
import '../../../player/control/gesture_math.dart';
import 'gesture_map_content.dart';

/// The gesture tutorial: the player's real zones, labelled, over whatever is
/// behind (the paused video on the first open, the settings list when reopened).
///
/// The zone geometry is computed from the SAME constants the gestures use
/// ([kTapCenterStart], [kCenterRotateFraction], [kLateralEdgeMargin]), so the
/// drawing cannot drift from the behavior.
class GestureMapScreen extends ConsumerStatefulWidget {
  const GestureMapScreen({super.key});

  @override
  ConsumerState<GestureMapScreen> createState() => _GestureMapScreenState();
}

class _GestureMapScreenState extends ConsumerState<GestureMapScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next(int total) {
    if (_index >= total - 1) {
      Navigator.of(context).pop();
      return;
    }
    _controller.nextPage(
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final l10n = context.l10n;
    final pages = gestureMapPages(
      l10n,
      ref.watch(settingsProvider),
      pipSupported: ref.watch(pipSupportedProvider).value ?? false,
    );
    final last = _index >= pages.length - 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: Colors.black.withValues(alpha: 0.82),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        pages[_index].title.toUpperCase(),
                        style: TextStyle(
                          color: accent,
                          fontSize: 10.5,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${_index + 1}/${pages.length}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _index = i),
                  children: [
                    for (final page in pages)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                        child: page.hints.any((h) =>
                                h.zone == MapZone.topBar ||
                                h.zone == MapZone.bottomBar)
                            ? _ButtonsPage(page: page, accent: accent)
                            : _ZonesPage(page: page, accent: accent),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      Container(
                        width: i == _index ? 18 : 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(
                          color: i == _index
                              ? accent
                              : Colors.white.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _next(pages.length),
                      style: TextButton.styleFrom(
                        foregroundColor: accent,
                        backgroundColor: accent.withValues(alpha: 0.10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(100),
                          side: BorderSide(color: accent.withValues(alpha: 0.5)),
                        ),
                      ),
                      child: Text(
                        last ? l10n.playerTutorialDoneAction : l10n.playerTutorialNextAction,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A page whose hints are anchored to screen zones (pages "Toques" and
/// "Arrastres"): the diagram on top, the footer legend beneath.
class _ZonesPage extends StatelessWidget {
  final GestureMapPage page;
  final Color accent;
  const _ZonesPage({required this.page, required this.accent});

  @override
  Widget build(BuildContext context) {
    final zoned = page.hints.where((h) => h.zone != MapZone.footer).toList();
    final footer = page.hints.where((h) => h.zone == MapZone.footer).toList();
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => Stack(
              children: [
                // The screen outline the zones live in.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12)),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                for (final hint in zoned)
                  ..._positioned(hint, c.maxWidth, c.maxHeight),
              ],
            ),
          ),
        ),
        for (final hint in footer)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _FooterRow(label: hint.label, accent: accent),
          ),
      ],
    );
  }

  /// Places one hint using the real gesture geometry. Returns a list because the
  /// lateral-edge hint draws two strips plus its label.
  List<Widget> _positioned(GestureHint hint, double w, double h) {
    switch (hint.zone) {
      case MapZone.leftThird:
        return [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: w * kTapCenterStart,
            child: _ZoneBox(hint: hint, accent: accent),
          ),
        ];
      case MapZone.centerThird:
        return [
          Positioned(
            left: w * kTapCenterStart,
            top: 0,
            bottom: 0,
            width: w * (kTapCenterEnd - kTapCenterStart),
            child: _ZoneBox(hint: hint, accent: accent),
          ),
        ];
      case MapZone.rightThird:
        return [
          Positioned(
            left: w * kTapCenterEnd,
            top: 0,
            bottom: 0,
            right: 0,
            child: _ZoneBox(hint: hint, accent: accent),
          ),
        ];
      // The halves are the base layer of the drags page: full height, label near
      // the top so the bands drawn over them stay readable.
      case MapZone.leftHalf:
        return [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: w / 2,
            child: _ZoneBox(hint: hint, accent: accent, align: 0.22),
          ),
        ];
      case MapZone.rightHalf:
        return [
          Positioned(
            left: w / 2,
            top: 0,
            bottom: 0,
            right: 0,
            child: _ZoneBox(hint: hint, accent: accent, align: 0.22),
          ),
        ];
      case MapZone.centerBand:
        return [
          Positioned(
            left: w * (0.5 - kCenterRotateFraction / 2),
            width: w * kCenterRotateFraction,
            top: h * 0.40,
            height: h * 0.24,
            child: _ZoneBox(hint: hint, accent: accent, dense: true),
          ),
        ];
      case MapZone.fullWidth:
        return [
          Positioned(
            left: 6,
            right: 6,
            top: h * 0.70,
            height: h * 0.16,
            child: _ZoneBox(hint: hint, accent: accent, dense: true),
          ),
        ];
      case MapZone.lateralEdges:
        return [
          for (final left in const [true, false])
            Positioned(
              left: left ? 0 : null,
              right: left ? null : 0,
              top: 0,
              bottom: 0,
              width: kLateralEdgeMargin,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 6,
            child: Center(
              child: _Pill(
                  label: hint.label, arrow: hint.arrow, accent: accent),
            ),
          ),
        ];
      case MapZone.footer:
      case MapZone.topBar:
      case MapZone.bottomBar:
        return const [];
    }
  }
}

/// An outlined zone rectangle with its label (and arrow) inside.
class _ZoneBox extends StatelessWidget {
  final GestureHint hint;
  final Color accent;

  /// Vertical position of the label inside the box, 0 = top, 1 = bottom.
  final double align;
  final bool dense;
  const _ZoneBox({
    required this.hint,
    required this.accent,
    this.align = 0.5,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Align(
        alignment: Alignment(0, align * 2 - 1),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8),
          child: _Label(
              label: hint.label, arrow: hint.arrow, accent: accent, dense: dense),
        ),
      ),
    );
  }
}

IconData? _arrowIcon(HintArrow? arrow) => switch (arrow) {
      HintArrow.vertical => Icons.swap_vert,
      HintArrow.horizontal => Icons.swap_horiz,
      HintArrow.down => Icons.south,
      null => null,
    };

class _Label extends StatelessWidget {
  final String label;
  final HintArrow? arrow;
  final Color accent;
  final bool dense;
  const _Label({
    required this.label,
    required this.arrow,
    required this.accent,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final icon = _arrowIcon(arrow);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) Icon(icon, size: dense ? 16 : 20, color: accent),
        if (icon != null) const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontSize: dense ? 10.5 : 11.5,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

/// Rounded label used where a zone box would not fit (the lateral edges).
class _Pill extends StatelessWidget {
  final String label;
  final HintArrow? arrow;
  final Color accent;
  const _Pill({required this.label, required this.arrow, required this.accent});

  @override
  Widget build(BuildContext context) {
    final icon = _arrowIcon(arrow);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: 14, color: accent),
          if (icon != null) const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterRow extends StatelessWidget {
  final String label;
  final Color accent;
  const _FooterRow({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

/// The "Botones" page: each bar drawn as the icon row it really is, followed by
/// what each icon does. It does NOT mount the real TopBar/BottomBar — those read
/// player state that does not exist when the map is opened from Settings.
class _ButtonsPage extends StatelessWidget {
  final GestureMapPage page;
  final Color accent;
  const _ButtonsPage({required this.page, required this.accent});

  static String _svg(MapIcon icon) => switch (icon) {
        MapIcon.back => KivoIcons.back,
        MapIcon.info => KivoIcons.info,
        MapIcon.subtitles => KivoIcons.subtitles,
        MapIcon.pip => KivoIcons.pip,
        MapIcon.audio => KivoIcons.audio,
        MapIcon.more => KivoIcons.more,
        MapIcon.speed => KivoIcons.speed,
        MapIcon.lock => KivoIcons.lock,
        MapIcon.aspect => KivoIcons.aspect,
        MapIcon.rotate => KivoIcons.rotate,
      };

  @override
  Widget build(BuildContext context) {
    final top = page.hints.where((h) => h.zone == MapZone.topBar).toList();
    final bottom = page.hints.where((h) => h.zone == MapZone.bottomBar).toList();
    final footer = page.hints.where((h) => h.zone == MapZone.footer).toList();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section(context.l10n.playerTutorialTopBarSection, top),
          const SizedBox(height: 14),
          _section(context.l10n.playerTutorialBottomBarSection, bottom),
          for (final hint in footer)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _FooterRow(label: hint.label, accent: accent),
            ),
        ],
      ),
    );
  }

  Widget _section(String title, List<GestureHint> hints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The bar as the user sees it, icons in the real order.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.06),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final hint in hints)
                  KivoIcon(_svg(hint.icon!), size: 20, color: Colors.white),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.34),
                fontSize: 9.5,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final hint in hints)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  KivoIcon(_svg(hint.icon!), size: 17, color: Colors.white70),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hint.label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
}
