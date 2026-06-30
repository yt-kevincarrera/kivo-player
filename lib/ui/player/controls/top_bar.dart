import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/icons/kivo_icons.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../player/open/video_source.dart';

class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  String _name(String? path) {
    if (path == null) return 'Kivo';
    final p = path.replaceAll('\\', '/');
    final i = p.lastIndexOf('/');
    return i < 0 ? p : p.substring(i + 1);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentVideoProvider);
    final infoOn = ref.watch(settingsProvider).showInfoOverlay;
    final accent = Color(ref.watch(settingsProvider).accentColor);
    return Row(
      children: [
        IconButton(
          color: Colors.white,
          tooltip: 'Atrás',
          icon: KivoIcon(KivoIcons.back, size: 24, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Text(_name(session?.path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
        IconButton(
          color: infoOn ? accent : Colors.white54,
          tooltip: infoOn ? 'Ocultar información en pantalla' : 'Mostrar información en pantalla',
          icon: KivoIcon(KivoIcons.info, size: 24, color: infoOn ? accent : Colors.white54),
          onPressed: () {
            final s = ref.read(settingsProvider);
            ref.read(settingsProvider.notifier).set(s.copyWith(showInfoOverlay: !s.showInfoOverlay));
          },
        ),
        // Disabled until later plans (Plan 3 / Hito 3)
        IconButton(color: Colors.white38, tooltip: 'Subtítulos', icon: KivoIcon(KivoIcons.subtitles, size: 24, opacity: 0.38), onPressed: null),
        IconButton(color: Colors.white38, tooltip: 'Imagen en imagen', icon: KivoIcon(KivoIcons.pip, size: 24, opacity: 0.38), onPressed: null),
        IconButton(color: Colors.white38, tooltip: 'Audio', icon: KivoIcon(KivoIcons.audio, size: 24, opacity: 0.38), onPressed: null),
        IconButton(color: Colors.white38, tooltip: 'Más opciones', icon: KivoIcon(KivoIcons.more, size: 24, opacity: 0.38), onPressed: null),
      ],
    );
  }
}
