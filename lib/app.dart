import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/navigation.dart';
import 'core/settings/settings_provider.dart';
import 'core/theme/kivo_theme.dart';
import 'core/update/update_providers.dart';
import 'player/autoplay/autoplay_coordinator.dart';
import 'player/background/background_playback.dart';
import 'ui/home/home_shell.dart';
import 'ui/update/update_dialog.dart';

class KivoApp extends ConsumerStatefulWidget {
  const KivoApp({super.key});
  @override
  ConsumerState<KivoApp> createState() => _KivoAppState();
}

class _KivoAppState extends ConsumerState<KivoApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoCheck());
  }

  Future<void> _maybeAutoCheck() async {
    final s = ref.read(settingsProvider);
    if (!shouldAutoCheck(
      enabled: s.autoCheckUpdates,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      lastMs: s.lastUpdateCheckMs,
    )) return;
    final result = await ref.read(updateControllerProvider).check();
    if (result.status != UpdateStatus.available) return;
    final ctx = kivoNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    showUpdateDialog(ctx, ref, result.info!);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(backgroundPlaybackProvider);
    ref.watch(autoplayCoordinatorProvider);
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final accent = Color(ref.watch(settingsProvider.select((s) => s.accentColor)));
    return MaterialApp(
      navigatorKey: kivoNavigatorKey,
      title: 'Kivo',
      debugShowCheckedModeBanner: false,
      theme: KivoTheme.light(accent: accent),
      darkTheme: KivoTheme.dark(accent: accent),
      themeMode: themeModeFor(mode),
      home: const HomeShell(),
    );
  }
}
