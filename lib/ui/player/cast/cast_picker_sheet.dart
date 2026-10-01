import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../platform/cast_platform_provider.dart';
import '../../../platform/interfaces/cast_platform.dart';
import '../../../player/cast/cast_controller.dart';
import '../../../player/cast/upnp.dart';

/// Lists the TVs on the Wi-Fi and returns the one picked (null if none).
Future<DlnaRenderer?> showCastPicker(BuildContext context) =>
    showModalBottomSheet<DlnaRenderer>(
      context: context,
      showDragHandle: true,
      builder: (_) => const CastPickerSheet(),
    );

class CastPickerSheet extends ConsumerStatefulWidget {
  const CastPickerSheet({super.key});

  @override
  ConsumerState<CastPickerSheet> createState() => _CastPickerSheetState();
}

class _CastPickerSheetState extends ConsumerState<CastPickerSheet> {
  List<DlnaRenderer> _found = const [];
  bool _searching = false;
  StreamSubscription<List<DlnaRenderer>>? _sub;
  // Read once: dispose must not touch ref.
  late final CastPlatform _platform = ref.read(castPlatformProvider);

  @override
  void initState() {
    super.initState();
    _search();
  }

  void _search() {
    _sub?.cancel();
    setState(() {
      _searching = true;
      _found = const [];
    });
    final platform = _platform;
    platform.multicastLock(true);
    _sub = ref
        .read(tvDiscoveryProvider)
        .search()
        .listen(
          (list) {
            if (mounted) setState(() => _found = list);
          },
          onError: (_) {},
          onDone: () {
            platform.multicastLock(false);
            if (mounted) setState(() => _searching = false);
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _platform.multicastLock(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.castPickerTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final r in _found)
              ListTile(
                key: ValueKey('cast-${r.id}'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.tv, color: cs.secondary),
                title: Text(r.name),
                subtitle: r.model == null || r.model == r.name
                    ? null
                    : Text(r.model!),
                onTap: () => Navigator.of(context).pop(r),
              ),
            if (_searching)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(l10n.castPickerSearching)),
                  ],
                ),
              )
            else if (_found.isEmpty) ...[
              Text(
                l10n.castPickerEmptyTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.castPickerEmptyBody,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ],
            if (!_searching)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _search,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.castPickerRetry),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              l10n.castPickerNote,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
