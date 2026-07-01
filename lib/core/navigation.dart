import 'package:flutter/material.dart';

/// The app's root Navigator, used for navigating from global overlays (like
/// the mini-player) that sit outside the Navigator's own subtree.
///
/// `MaterialApp.builder`'s `context` parameter is an ANCESTOR of the
/// Navigator it builds, not a descendant — and a widget placed inside that
/// builder's returned tree (e.g. `Stack(children: [navigatorChild,
/// MiniPlayerBar()])`) ends up a SIBLING of the Navigator, not a descendant
/// of it either. `Navigator.of(context)` called from such a widget cannot
/// find the app's Navigator and fails (silently, from the tap's
/// perspective — the exception is caught by Flutter's gesture error
/// handling). A GlobalKey attached directly to `MaterialApp(navigatorKey:)`
/// works from anywhere, regardless of tree position.
final kivoNavigatorKey = GlobalKey<NavigatorState>();
