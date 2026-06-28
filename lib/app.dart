import 'package:flutter/material.dart';
import 'core/theme/kivo_theme.dart';
import 'ui/home/open_screen.dart';

class KivoApp extends StatelessWidget {
  const KivoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kivo',
      debugShowCheckedModeBanner: false,
      theme: KivoTheme.dark(),
      home: const OpenScreen(),
    );
  }
}
