import 'package:flutter/material.dart';
import '../../tv/tv_input_mode.dart';
import '../../tv/tv_page.dart';

/// Retains each section's settings model while giving TV a complete page
/// presentation, including its nested routes. Phone scaffolds stay the same.
class SettingsSectionPage extends StatelessWidget {
  const SettingsSectionPage({
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });
  final String title;
  final Widget body;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => TvInputMode.of(context)
      ? TvPage(title: title, actions: actions ?? [], child: body)
      : Scaffold(
          appBar: AppBar(title: Text(title), actions: actions),
          body: body,
        );
}
