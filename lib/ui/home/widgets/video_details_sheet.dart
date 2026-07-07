import 'package:flutter/material.dart';
import '../../../core/format.dart';
import '../../../platform/interfaces/media_indexer.dart';

void showVideoDetails(BuildContext context, VideoItem v) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (ctx) {
      final res = (v.width > 0 && v.height > 0) ? '${v.width}×${v.height}' : '—';
      final date = v.dateAddedMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(v.dateAddedMs).toString().split('.').first
          : '—';
      final folder = v.path.isNotEmpty ? v.path : v.folder;
      final rows = <(String, String)>[
        ('Nombre', v.name),
        ('Carpeta', folder),
        ('Tamaño', fmtSize(v.sizeBytes)),
        ('Duración', fmtDuration(Duration(milliseconds: v.durationMs))),
        ('Resolución', res),
        ('Agregado', date),
        ('URI', v.uri),
      ];
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Detalles',
                  style: TextStyle(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 92,
                      child: Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    ),
                    Expanded(
                      child: SelectableText(value, style: TextStyle(color: cs.onSurface, fontSize: 13)),
                    ),
                  ]),
                ),
            ],
          ),
        ),
      );
    },
  );
}
