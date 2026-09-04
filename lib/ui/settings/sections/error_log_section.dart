import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_log.dart';
import '../../../core/errors/error_log_provider.dart';
import '../../../l10n/l10n.dart';

/// The last failures Kivo recorded, so a reported code can be traced back to
/// what actually went wrong on that device.
class ErrorLogSection extends ConsumerStatefulWidget {
  const ErrorLogSection({super.key});

  @override
  ConsumerState<ErrorLogSection> createState() => _ErrorLogSectionState();
}

class _ErrorLogSectionState extends ConsumerState<ErrorLogSection> {
  final _expanded = <int>{};

  String _age(BuildContext context, int timestampMs) {
    final l10n = context.l10n;
    final d = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(timestampMs));
    if (d.inMinutes < 1) return l10n.settingsErrorLogAgeJustNow;
    if (d.inHours < 1) return l10n.settingsErrorLogAgeMinutes(d.inMinutes);
    if (d.inDays < 1) return l10n.settingsErrorLogAgeHours(d.inHours);
    return l10n.settingsErrorLogAgeDays(d.inDays);
  }

  Future<void> _copyAll(List<ErrorLogEntry> entries) async {
    final l10n = context.l10n;
    final text = entries
        .map((e) =>
            '${e.code} ${e.op} · ${l10n.settingsErrorLogDetailLine(e.appVersion, e.androidSdk)}\n${e.detail}')
        .join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsErrorLogCopiedSnackbar)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final log = ref.watch(errorLogProvider);
    final entries = log.entries();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsAboutErrorLogTitle),
        actions: [
          if (entries.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: l10n.settingsErrorLogCopyAllTooltip,
              onPressed: () => _copyAll(entries),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.settingsErrorLogClearTooltip,
              onPressed: () async {
                await log.clear();
                if (mounted) setState(() => _expanded.clear());
              },
            ),
          ],
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Text(l10n.settingsErrorLogEmpty,
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _entryTile(context, entries[i], i, cs),
            ),
    );
  }

  Widget _entryTile(BuildContext context, ErrorLogEntry e, int i, ColorScheme cs) {
    final open = _expanded.contains(i);
    return Container(
      decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(13)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () =>
                setState(() => open ? _expanded.remove(i) : _expanded.add(i)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Text(e.code,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: cs.secondary)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${e.op} · ${_age(context, e.timestampMs)}',
                        style: TextStyle(
                            fontSize: 11.5, color: cs.onSurfaceVariant)),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more,
                      size: 20, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.settingsErrorLogDetailLine(e.appVersion, e.androidSdk),
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(9)),
                    child: SelectableText(
                      e.detail,
                      style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.4,
                          color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
