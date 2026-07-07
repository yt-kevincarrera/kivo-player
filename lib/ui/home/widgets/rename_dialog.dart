import 'package:flutter/material.dart';
import '../../../platform/interfaces/media_indexer.dart';
import '../../../player/library/rename_util.dart';

/// Prompts for a new base name (extension shown, locked). Returns the sanitized
/// base name, or null if cancelled / unchanged.
Future<String?> showRenameDialog(BuildContext context, VideoItem v) async {
  final split = splitNameExt(v.name);
  final controller = TextEditingController(text: split.base);
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          final sanitized = sanitizeRenameTarget(controller.text);
          final valid = sanitized != null && sanitized != split.base;
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: const Text('Renombrar'),
            content: Row(children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (split.ext.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(split.ext, style: TextStyle(color: cs.onSurfaceVariant)),
                ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
              TextButton(
                onPressed: valid ? () => Navigator.pop(ctx, sanitized) : null,
                child: const Text('Guardar'),
              ),
            ],
          );
        });
      },
    );
  } finally {
    // The dialog route's pop-exit transition is still animating widgets
    // (e.g. TextField internals) that reference `controller` for a frame or
    // two after `showDialog`'s future resolves. Disposing synchronously here
    // races that transition and throws "used after being disposed". Deferring
    // to a post-frame callback lets the route finish being removed first.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }
}
