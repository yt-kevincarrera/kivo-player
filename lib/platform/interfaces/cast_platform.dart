/// The Android half of "Enviar a la TV": serving the video to the TV,
/// the multicast lock for finding it, and keeping the cast alive in the
/// background. UPnP itself is Dart (`lib/player/cast/`).
abstract class CastPlatform {
  /// Hold (or release) Android's multicast lock — without it the replies
  /// to a TV search are dropped.
  Future<void> multicastLock(bool on);

  /// Start serving [source] (a `content://` uri or a file path) over HTTP.
  Future<ServedVideo> serve(String source);
  Future<void> stopServing();

  /// The foreground service + notification that keep the cast going with
  /// the screen off; [device] is shown in the notification.
  Future<void> keepAlive(bool on, {String device = ''});

  /// The notification's "Dejar de enviar".
  Stream<void> get stopRequests;
}

class ServedVideo {
  final int port;
  final String path;
  final String mime;
  final int size;
  const ServedVideo({
    required this.port,
    required this.path,
    required this.mime,
    required this.size,
  });
}
