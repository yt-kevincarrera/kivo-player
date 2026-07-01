import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while the player is minimized to the global mini-bar instead of
/// showing full-screen. Set on any exit (back button, system back,
/// swipe-down); reset to false whenever a video enters full-screen.
final playerMinimizedProvider = StateProvider<bool>((ref) => false);

/// The freeze-frame preview captured at the moment of minimizing, shown by
/// the mini-bar. Null before any minimize, or if extraction failed/hasn't
/// completed. Reset to null on every fresh player entry.
final miniPlayerThumbnailProvider = StateProvider<Uint8List?>((ref) => null);

/// The resume key (`VideoSession.resumeKey`) of whichever session is
/// currently minimized, or null. Distinguishes "expanding the SAME session
/// that's minimized" (skip re-opening — the engine may already be playing
/// further along than the resume store, e.g. via the mini-bar's own
/// play/pause button) from "opening a DIFFERENT video while one happens to
/// be minimized" (a normal fresh open must still happen). Reset to null on
/// every fresh player entry.
final minimizedSessionKeyProvider = StateProvider<String?>((ref) => null);
