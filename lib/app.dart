import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/navigation.dart';
import 'core/settings/settings_provider.dart';
import 'core/theme/kivo_theme.dart';
import 'ui/home/library_screen.dart';
import 'ui/mini_player/mini_player_bar.dart';

class KivoApp extends ConsumerWidget {
  const KivoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp(
      navigatorKey: kivoNavigatorKey,
      title: 'Kivo',
      debugShowCheckedModeBanner: false,
      theme: KivoTheme.light(),
      darkTheme: KivoTheme.dark(),
      themeMode: themeModeFor(mode),
      home: const LibraryScreen(),
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          const Positioned(left: 0, right: 0, bottom: 0, child: MiniPlayerBar()),
        ],
      ),
    );
  }
}
