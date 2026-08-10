import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_log.dart';
import '../../../core/errors/error_log_provider.dart';

/// The last failures Kivo recorded, so a reported code can be traced back to
/// what actually went wrong on that device.
class ErrorLogSection extends ConsumerStatefulWidget {
  const ErrorLogSection({super.key});

  @override
  ConsumerState<ErrorLogSection> createState() => _ErrorLogSectionState();
}

class _ErrorLogSectionState extends ConsumerState<ErrorLogSection> {
  final _expanded = <int>{};

  String _age(int timestampMs) {
    final d = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(timestampMs));
    if (d.inMinutes < 1) return 'ahora mismo';
    if (d.inHours < 1) return 'hace ${d.inMinutes} min';
    if (d.inDays < 1) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  Future<void> _copyAll(List<ErrorLogEntry> entries) async {
    final text = entries
        .map((e) => '${e.code} ${e.op} · Kivo ${e.appVersion} · '
            'API ${e.androidSdk}\n${e.detail}')
        .join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Registro copiado')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final log = ref.watch(errorLogProvider);
    final entries = log.entries();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de errores'),
        actions: [
          if (entries.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.copy_outlined),
              tooltip: 'Copiar todo',
              onPressed: () => _copyAll(entries),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Borrar registro',
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
              child: Text('Sin errores registrados',
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _entryTile(entries[i], i, cs),
            ),
    );
  }

  Widget _entryTile(ErrorLogEntry e, int i, ColorScheme cs) {
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
                    child: Text('${e.op} · ${_age(e.timestampMs)}',
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
                  Text('Kivo ${e.appVersion} · Android API ${e.androidSdk}',
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
