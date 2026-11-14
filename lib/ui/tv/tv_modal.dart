import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/television_provider.dart';

/// Existing feature panels remain shared. A TV opens them as a centered,
/// bounded dialog with readable text; the phone keeps its original sheet.
Future<T?> showTvAwareBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool isScrollControlled = false,
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
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: backgroundColor,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: MediaQuery.sizeOf(ctx).height * .85,
        ),
        child: MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.2,
          child: Builder(builder: builder),
        ),
      ),
    ),
  );
}
