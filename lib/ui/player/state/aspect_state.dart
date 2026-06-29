import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';

enum AspectMode { fit, fill, stretch }

BoxFit boxFitFor(AspectMode m) => switch (m) {
      AspectMode.fit => BoxFit.contain,
      AspectMode.fill => BoxFit.cover,
      AspectMode.stretch => BoxFit.fill,
    };

AspectMode nextAspect(AspectMode m) =>
    AspectMode.values[(m.index + 1) % AspectMode.values.length];

String aspectIconFor(AspectMode m) => switch (m) {
      AspectMode.fit => KivoIcons.aspectFit,
      AspectMode.fill => KivoIcons.aspectFill,
      AspectMode.stretch => KivoIcons.aspectStretch,
    };

String aspectLabelFor(AspectMode m) => switch (m) {
      AspectMode.fit => 'Ajustar',
      AspectMode.fill => 'Llenar',
      AspectMode.stretch => 'Estirar',
    };

AspectMode aspectFromSetting(String s) => switch (s) {
      'fill' => AspectMode.fill,
      'stretch' => AspectMode.stretch,
      _ => AspectMode.fit,
    };

class AspectNotifier extends Notifier<AspectMode> {
  @override
  AspectMode build() => aspectFromSetting(ref.read(settingsProvider).defaultAspectMode);
  void cycle() => state = nextAspect(state);
}

final aspectModeProvider =
    NotifierProvider<AspectNotifier, AspectMode>(AspectNotifier.new);
