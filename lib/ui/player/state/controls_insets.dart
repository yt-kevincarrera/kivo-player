import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Measured heights of the player's top and bottom control bars (including
/// their gradient padding), so the subtitles can step out of their way by
/// exactly that much while the controls show — never a guessed constant.
final controlsTopInsetProvider = StateProvider<double>((ref) => 0);
final controlsBottomInsetProvider = StateProvider<double>((ref) => 0);

/// Reports its child's height after each layout, only when it changed.
class MeasureHeight extends StatefulWidget {
  const MeasureHeight({super.key, required this.onHeight, required this.child});

  final ValueChanged<double> onHeight;
  final Widget child;

  @override
  State<MeasureHeight> createState() => _MeasureHeightState();
}

class _MeasureHeightState extends State<MeasureHeight> {
  double? _last;

  void _report() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final h = box.size.height;
    if (h == _last) return;
    _last = h;
    widget.onHeight(h);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    return widget.child;
  }
}
