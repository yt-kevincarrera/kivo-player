import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/theme/kivo_theme.dart';

/// The single empty state the library uses everywhere a list can legitimately
/// come back with nothing: no videos on the device, a filter that hid them all,
/// a folder emptied by deleting its last video, a search with no hits.
///
/// Without it those paths render a scroll view whose slivers are all empty —
/// a literally blank body with no explanation and no way out. Every variant
/// therefore names what happened AND offers the action that undoes it.
///
/// Metrics deliberately echo [FailureView] (same title size/weight, same 18px
/// gap before the actions) so "nothing here" and "something broke" read as
/// siblings rather than as two unrelated screens.
class LibraryEmptyState extends ConsumerWidget {
  const LibraryEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Filled, accent-colored: the action that resolves the emptiness.
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  /// Quiet text button: the fallback route, if there is one.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    // Follows whatever accent is set in Ajustes, like the filter chips do.
    final accent = Color(ref.watch(settingsProvider).accentColor);
    final hasActions = primaryLabel != null || secondaryLabel != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.12),
              ),
              child: Icon(icon, size: 34, color: accent),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            if (hasActions) const SizedBox(height: 18),
            if (primaryLabel != null)
              FilledButton(
                onPressed: onPrimary,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: onAccent(accent),
                ),
                child: Text(primaryLabel!),
              ),
            if (secondaryLabel != null)
              TextButton(
                onPressed: onSecondary,
                child: Text(
                  secondaryLabel!,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
