import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/update/update_providers.dart';
import '../../../platform/app_installer_provider.dart';
import '../../update/update_dialog.dart';
import '../widgets/setting_tiles.dart';

class AboutSection extends ConsumerStatefulWidget {
  const AboutSection({super.key});
  @override
  ConsumerState<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends ConsumerState<AboutSection> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final result = await ref.read(updateControllerProvider).check(manual: true);
    if (!mounted) return;
    setState(() => _checking = false);
    final messenger = ScaffoldMessenger.of(context);
    switch (result.status) {
      case UpdateStatus.available:
        showUpdateDialog(context, ref, result.info!);
      case UpdateStatus.upToDate:
        messenger.showSnackBar(const SnackBar(content: Text('Estás al día ✓')));
      case UpdateStatus.error:
        messenger.showSnackBar(const SnackBar(content: Text('No se pudo comprobar')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final auto = ref.watch(settingsProvider.select((s) => s.autoCheckUpdates));
    return Scaffold(
      appBar: AppBar(title: const Text('Acerca de')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 28),
        children: [
          Center(
            child: Column(children: [
              Text('Kivo', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: cs.onSurface)),
              const SizedBox(height: 6),
              FutureBuilder<String>(
                future: ref.read(appInstallerProvider).appVersion(),
                builder: (_, snap) => Text('Versión ${snap.data ?? '…'}',
                    style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
              ),
              const SizedBox(height: 4),
              Text('Reproductor de video local', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              const SizedBox(height: 20),
              Text('Por Kevin Carrera', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(height: 2),
              SelectableText('kevin.ccdo@gmail.com', style: TextStyle(fontSize: 12.5, color: cs.secondary)),
            ]),
          ),
          const SizedBox(height: 28),
          ListTile(
            leading: _checking
                ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: cs.secondary))
                : Icon(Icons.system_update_outlined, color: cs.onSurfaceVariant),
            title: const Text('Buscar actualizaciones'),
            onTap: _checking ? null : _check,
          ),
          SettingSwitch(
            title: 'Buscar automáticamente',
            subtitle: 'Comprueba al abrir, máximo una vez al día',
            value: auto,
            onChanged: (v) => ref.read(settingsProvider.notifier)
                .set(ref.read(settingsProvider).copyWith(autoCheckUpdates: v)),
          ),
        ],
      ),
    );
  }
}
