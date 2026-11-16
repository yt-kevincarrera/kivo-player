import 'package:flutter/material.dart';
import '../../l10n/l10n.dart';
import 'tv_focusable.dart';

/// The same spacious header and return target on every full-screen TV task.
class TvPage extends StatelessWidget {
  const TvPage({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
  });
  final String title;
  final Widget child;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 28, 48, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TvButton(
                  label: context.l10n.commonGoBack,
                  icon: Icons.arrow_back,
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 30),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ...actions,
              ],
            ),
            const SizedBox(height: 30),
            Expanded(child: FocusTraversalGroup(child: child)),
          ],
        ),
      ),
    ),
  );
}
