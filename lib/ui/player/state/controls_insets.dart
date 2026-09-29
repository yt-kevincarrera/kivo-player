import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Measured heights of the player's top and bottom control bars (including
/// their gradient padding), so the subtitles can step out of their way by
/// exactly that much while the controls show — never a guessed constant.
final controlsTopInsetProvider = StateProvider<double>((ref) => 0);
final controlsBottomInsetProvider = StateProvider<double>((ref) => 0);

/// Reports its child's height whenever layout changes it — from the render
/// object itself, so a rotation or a bar growing while shown is caught even
/// when nothing rebuilds this widget (ControlsOverlay is const).
class MeasureHeight extends SingleChildRenderObjectWidget {
  const MeasureHeight({super.key, required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(
          BuildContext context, RenderMeasureHeight renderObject) =>
      renderObject.onHeight = onHeight;
}

class RenderMeasureHeight extends RenderProxyBox {
  RenderMeasureHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    // Never mutate providers during layout: report after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(h));
  }
}
