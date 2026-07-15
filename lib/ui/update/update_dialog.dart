import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/update/update_info.dart';
import '../../core/update/update_providers.dart';
import '../../platform/interfaces/app_installer.dart';

Future<void> showUpdateDialog(BuildContext context, WidgetRef ref, UpdateInfo info) {
  final controller = ref.read(updateControllerProvider);
  final messenger = ScaffoldMessenger.of(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text('Nueva versión ${info.version}'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              info.notes.trim().isEmpty ? 'Hay una versión más reciente disponible.' : info.notes.trim(),
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () { controller.skip(info.version); Navigator.pop(ctx); },
            child: const Text('Omitir esta versión'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ahora no')),
          FilledButton(
            onPressed: info.apkUrl == null
                ? () { controller.openInBrowser(info); Navigator.pop(ctx); }
                : () async {
                    final outcome = await controller.startUpdate(info);
                    Navigator.pop(ctx);
                    switch (outcome) {
                      case InstallOutcome.started:
                        messenger.showSnackBar(const SnackBar(content: Text('Descargando actualización…')));
                      case InstallOutcome.needsPermission:
                        messenger.showSnackBar(const SnackBar(
                            content: Text('Permite instalar apps para continuar, luego reintenta.')));
                      case InstallOutcome.failed:
                        controller.openInBrowser(info);
                        messenger.showSnackBar(const SnackBar(content: Text('Abriendo la descarga en el navegador…')));
                    }
                  },
            child: const Text('Descargar'),
          ),
        ],
      );
    },
  );
}
