import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/settings/kivo_settings.dart';
import '../../core/settings/settings_provider.dart';
import '../../l10n/l10n.dart';

/// Window space, rather than orientation or the device's shortest side, decides
/// the shell. A portrait tablet and a landscape phone both benefit from a rail.
bool usesSideNavigation(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 600;

bool usesWideLibrary(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 600;

int libraryDensity(BuildContext context, KivoSettings settings) =>
    usesWideLibrary(context)
    ? settings.wideLibraryDensity
    : settings.libraryColumns;

Future<void> setLibraryDensity(
  BuildContext context,
  WidgetRef ref,
  int density,
) {
  final settings = ref.read(settingsProvider);
  return ref
      .read(settingsProvider.notifier)
      .set(
        usesWideLibrary(context)
            ? settings.copyWith(wideLibraryDensity: density)
            : settings.copyWith(libraryColumns: density),
      );
}

/// The grid uses its OWN constraints, after the navigation rail and padding.
/// Density 0 is an explicit list on wide windows. Phone settings retain their
/// historical meaning (1 = list, 2/3 = columns).
int libraryGridColumns({
  required double width,
  required bool wide,
  required int density,
  double textScale = 1,
}) {
  if (wide ? density == 0 : density == 1) return 1;
  final scale = math.max(1.0, textScale);
  if (!wide) return (density / scale).floor().clamp(1, density);
  final target = switch (density) {
    1 => 240.0,
    3 => 156.0,
    _ => 200.0,
  };
  return ((width + 12) / (target * scale + 12)).floor().clamp(
    1,
    wide ? 8 : density,
  );
}

List<(int, String)> wideDensityOptions(BuildContext context) => [
  (1, context.l10n.libraryDensityComfortable),
  (2, context.l10n.libraryDensityBalanced),
  (3, context.l10n.libraryDensityCompact),
  (0, context.l10n.libraryDensityList),
];

class LibraryDensityButton extends ConsumerWidget {
  const LibraryDensityButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    if (!usesWideLibrary(context)) {
      final next = settings.libraryColumns % 3 + 1;
      return IconButton(
        tooltip: context.l10n.libraryDensityTooltip(next),
        icon: const Icon(Icons.grid_view),
        onPressed: () => setLibraryDensity(context, ref, next),
      );
    }
    return PopupMenuButton<int>(
      tooltip: context.l10n.libraryDensityLabel,
      icon: const Icon(Icons.grid_view),
      initialValue: settings.wideLibraryDensity,
      onSelected: (value) => setLibraryDensity(context, ref, value),
      itemBuilder: (_) => [
        for (final option in wideDensityOptions(context))
          CheckedPopupMenuItem(
            value: option.$1,
            checked: settings.wideLibraryDensity == option.$1,
            child: Text(option.$2),
          ),
      ],
    );
  }
}
