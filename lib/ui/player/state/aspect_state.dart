import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../l10n/generated/app_localizations.dart';

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

// Takes the resolved AppLocalizations rather than a BuildContext: this file
// otherwise has no Flutter widget dependency, and the caller (bottom_bar.dart)
// already has a context to resolve it from.
String aspectLabelFor(AppLocalizations l10n, AspectMode m) => switch (m) {
      AspectMode.fit => l10n.playerAspectFit,
      AspectMode.fill => l10n.playerAspectFill,
      AspectMode.stretch => l10n.playerAspectStretch,
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
