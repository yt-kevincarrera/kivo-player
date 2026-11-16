import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/television_provider.dart';
import '../../l10n/l10n.dart';
import 'tv_panel.dart';

/// Shared feature panels use the TV's side panel or the original phone sheet.
Future<T?> showTvAwareBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool isScrollControlled = false,
  String? title,
}) {
  if (!ProviderScope.containerOf(
    context,
    listen: false,
  ).read(isTelevisionProvider)) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      backgroundColor: backgroundColor,
      shape: shape,
      isScrollControlled: isScrollControlled,
    );
  }
  return showTvPanel<T>(
    context: context,
    title: title ?? context.l10n.tvOptions,
    builder: builder,
  );
}
