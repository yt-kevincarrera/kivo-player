/// One "Continuar viendo" entry as the launcher shortcuts and the home-screen
/// widget show it.
class ContinueEntry {
  const ContinueEntry({
    required this.id,
    required this.uri,
    required this.name,
    required this.position,
    required this.fraction,
  });

  /// MediaStore id: what a tap on the shortcut/widget sends back.
  final String id;
  final String uri;
  final String name;

  /// Already formatted ("12:34"): Android only lays it out.
  final String position;
  final double fraction;

  Map<String, Object> toMap() => {
        'id': id,
        'uri': uri,
        'name': name,
        'position': position,
        'fraction': fraction,
      };

  @override
  bool operator ==(Object other) =>
      other is ContinueEntry &&
      other.id == id &&
      other.name == name &&
      other.position == position &&
      other.fraction == fraction;

  @override
  int get hashCode => Object.hash(id, name, position, fraction);
}

/// The app's surfaces outside the app: launcher shortcuts and the widget,
/// and the taps that come back from them.
abstract class LauncherBridge {
  /// What the shortcuts and the widget should show (newest first).
  Future<void> updateContinue(List<ContinueEntry> entries);

  /// The MediaStore id of a video a shortcut/widget asked to open when it
  /// launched the app, once; null if the app was opened normally.
  Future<String?> takeInitialOpenRequest();

  /// Videos asked for while the app was already running.
  Stream<String> get openRequests;
}
