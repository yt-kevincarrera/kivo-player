import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/l10n.dart';
import '../../player/open/video_source.dart';
import '../player/state/controls_visibility.dart';
import 'tv_focusable.dart';
import 'tv_input_mode.dart';

/// A single TV task lives beside the video. Back dismisses the route and
/// restores the invoking control; panels never change the player's session.
Future<T?> showTvPanel<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
}) {
  final reduce = MediaQuery.disableAnimationsOf(context);
  final invoker = FocusManager.instance.primaryFocus;
  final ownerRoute = ModalRoute.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final controls = container.read(currentVideoProvider) == null
      ? null
      : container.read(controlsVisibleProvider.notifier);
  controls?.hold();
  final route = RawDialogRoute<T>(
    settings: const RouteSettings(name: 'kivo-tv-panel'),
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black38,
    transitionDuration: reduce
        ? Duration.zero
        : const Duration(milliseconds: 180),
    transitionBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
    pageBuilder: (ctx, _, __) => TvInputMode(
      enabled: true,
      child: TvRemoteShortcuts(
        child: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: math.min(
              MediaQuery.sizeOf(ctx).width,
              (MediaQuery.sizeOf(ctx).width *
                      .38 *
                      MediaQuery.textScalerOf(ctx).scale(1))
                  .clamp(440, 800),
            ),
            child: Material(
              color: Theme.of(ctx).colorScheme.surface,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                  child: _TvPanelFocus(
                    builder: (backNode) => FocusTraversalGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TvOptionRow(
                            focusNode: backNode,
                            label: ctx.l10n.commonGoBack,
                            icon: Icons.arrow_back,
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (ctx, constraints) => MediaQuery(
                                data: MediaQuery.of(ctx).copyWith(
                                  size: Size(
                                    constraints.maxWidth,
                                    MediaQuery.sizeOf(ctx).height,
                                  ),
                                ),
                                child: Builder(builder: builder),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return Navigator.of(context, rootNavigator: true).push<T>(route).whenComplete(
    () async {
      // A pop result arrives before the outgoing route releases its focus
      // scope. Restore only after its transition, to the actual invoking row.
      await route.completed;
      controls?.release();
      if (context.mounted &&
          (ownerRoute?.isCurrent ?? true) &&
          invoker?.context != null &&
          invoker!.canRequestFocus) {
        invoker.requestFocus();
      }
    },
  );
}

/// Selected choices take their normal autofocus. Panels without a selected
/// choice still start with a visible target instead of an invisible scope.
class _TvPanelFocus extends StatefulWidget {
  const _TvPanelFocus({required this.builder});
  final Widget Function(FocusNode backNode) builder;
  @override
  State<_TvPanelFocus> createState() => _TvPanelFocusState();
}

class _TvPanelFocusState extends State<_TvPanelFocus> {
  final _scope = FocusScopeNode(debugLabel: 'tv-panel');
  final _back = FocusNode(debugLabel: 'tv-panel-back');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.applyFocusChangesIfNeeded();
      if (_scope.hasPrimaryFocus) _back.requestFocus();
    });
  }

  @override
  void dispose() {
    _back.dispose();
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FocusScope(node: _scope, autofocus: true, child: widget.builder(_back));
}

Future<String?> showTvTextInput(
  BuildContext context,
  String title, {
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  try {
    return await showTvPanel<String>(
      context: context,
      title: title,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(fontSize: 23),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) Navigator.of(ctx).pop(value.trim());
            },
          ),
          const SizedBox(height: 28),
          TvButton(
            label: ctx.l10n.commonSave,
            primary: true,
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

class TvOptionRow extends StatelessWidget {
  const TvOptionRow({
    super.key,
    required this.label,
    required this.onPressed,
    this.subtitle,
    this.value,
    this.selected,
    this.icon,
    this.autofocus = false,
    this.toggled,
    this.focusNode,
  });
  final String label;
  final String? subtitle, value;
  final bool? selected;
  final IconData? icon;
  final bool autofocus;
  final bool? toggled;
  final FocusNode? focusNode;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TvFocusable(
        label: subtitle?.isNotEmpty == true ? '$label. $subtitle' : label,
        focusNode: focusNode,
        value: value,
        selected: selected,
        toggled: toggled,
        autofocus: autofocus,
        onPressed: onPressed,
        scale: 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected == true
                ? c.onSurface.withValues(alpha: .06)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 25, color: c.onSurfaceVariant),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 22,
                        color: c.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle?.isNotEmpty == true) ...[
                      const SizedBox(height: 7),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 18,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 18),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * .32,
                  ),
                  child: Text(
                    value!,
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 20, color: c.onSurfaceVariant),
                  ),
                ),
              ],
              if (toggled != null) ...[
                const SizedBox(width: 20),
                Icon(
                  toggled! ? Icons.toggle_on : Icons.toggle_off,
                  size: 40,
                  color: toggled! ? c.primary : c.onSurfaceVariant,
                ),
              ],
              if (selected == true) ...[
                const SizedBox(width: 16),
                Icon(Icons.check, color: c.primary, size: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> showTvPanelChoices<T>(
  BuildContext context,
  String title,
  List<(T, String, String?)> choices, {
  T? selected,
}) => showTvPanel<T>(
  context: context,
  title: title,
  builder: (ctx) => ListView(
    padding: const EdgeInsets.all(5),
    children: [
      for (var i = 0; i < choices.length; i++)
        TvOptionRow(
          label: choices[i].$2,
          subtitle: choices[i].$3,
          selected: choices[i].$1 == selected,
          autofocus: choices.any((c) => c.$1 == selected)
              ? choices[i].$1 == selected
              : i == 0,
          onPressed: () => Navigator.of(ctx).pop(choices[i].$1),
        ),
    ],
  ),
);
