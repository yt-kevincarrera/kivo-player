import 'package:flutter/material.dart';

const kAppVersion = '1.0';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Acerca de')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Kivo', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 6),
            Text('Versión $kAppVersion', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('Reproductor de video local', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
