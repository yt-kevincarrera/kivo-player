import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The widest a column of settings rows should get. On a tablet or a TV a
/// full-width row puts its label and its switch a screen apart.
const double kReadableWidth = 720;

/// A tablet or a TV, as opposed to a phone in either orientation (the
/// shortest side is what tells them apart: a landscape phone is wide too).
/// The wide-screen layouts only apply here, so a phone looks as it always
/// has.
bool isLargeScreen(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= 600;

/// [base] plus whatever side padding keeps the content within
/// [kReadableWidth], centred. Unchanged on a phone.
EdgeInsets readablePadding(BuildContext context, EdgeInsets base) {
  if (!isLargeScreen(context)) return base;
  final extra =
      math.max(0.0, (MediaQuery.sizeOf(context).width - kReadableWidth) / 2);
  return base.copyWith(left: base.left + extra, right: base.right + extra);
}
