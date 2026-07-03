import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/navigation.dart';
import 'core/settings/settings_provider.dart';
import 'core/theme/kivo_theme.dart';
import 'player/background/background_playback.dart';
import 'ui/home/home_shell.dart';

class KivoApp extends ConsumerWidget {
  const KivoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(backgroundPlaybackProvider); // instantiate the coordinator once
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp(
      navigatorKey: kivoNavigatorKey,
      title: 'Kivo',
      debugShowCheckedModeBanner: false,
      theme: KivoTheme.light(),
      darkTheme: KivoTheme.dark(),
      themeMode: themeModeFor(mode),
      home: const HomeShell(),
    );
  }
}
