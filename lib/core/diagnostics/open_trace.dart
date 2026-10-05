import 'dart:ui' show FrameTiming;

/// A timeline of the last few video opens, for the problem report: what
/// happened when, how long each call into mpv blocked, and which frames
/// were slow while a video was starting. Kept in memory only; it leaves the
/// phone only inside a report the user sends (and sees first).
///
/// No file names: an open is described by where it came from, nothing more.
class OpenTrace {
  OpenTrace._();
  static final OpenTrace instance = OpenTrace._();

  static const _keepOpens = 4;
  static const _maxEvents = 120;

  /// How long after an open its events are still worth recording.
  static const window = Duration(seconds: 6);

  final List<_Open> _opens = [];

  _Open? get _fresh {
    if (_opens.isEmpty) return null;
    final o = _opens.last;
    return o.clock.elapsed <= window ? o : null;
  }

  /// A new open starts ([source]: library, strip, autoplay…).
  /// A begin right after another (the library open goes through the plain
  /// one) is the same open: the first, more specific source is kept.
  void begin(String source) {
    if (_opens.isNotEmpty && _opens.last.clock.elapsedMilliseconds < 50) return;
    _opens.add(_Open(source, DateTime.now()));
    if (_opens.length > _keepOpens) _opens.removeAt(0);
  }

  /// Something happened during the latest open (ignored once it is old).
  void mark(String event) {
    final o = _fresh;
    if (o == null || o.events.length >= _maxEvents) return;
    o.events.add((o.clock.elapsedMilliseconds, event));
  }

  /// A call that may block the UI thread; [run] is timed.
  Future<T> timed<T>(String what, Future<T> Function() run) async {
    if (_fresh == null) return run();
    final sw = Stopwatch()..start();
    try {
      return await run();
    } finally {
      mark('$what ${sw.elapsedMicroseconds}us');
    }
  }

  /// Frame timings from the engine: slow ones during a fresh open are kept.
  void frames(List<FrameTiming> timings) {
    if (_fresh == null) return;
    for (final t in timings) {
      final build = t.buildDuration.inMilliseconds;
      final raster = t.rasterDuration.inMilliseconds;
      if (build + raster >= 20) mark('slow frame build ${build}ms raster ${raster}ms');
    }
  }

  /// The report section.
  String report() {
    if (_opens.isEmpty) return '(no video opened since the app started)';
    final b = StringBuffer();
    for (final o in _opens) {
      b.writeln('${_hms(o.at)}  open from ${o.source}');
      for (final (ms, e) in o.events) {
        b.writeln('  +${ms.toString().padLeft(5)}ms  $e');
      }
    }
    return b.toString().trimRight();
  }

  /// For tests.
  void clear() => _opens.clear();

  static String _hms(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

class _Open {
  final String source;
  final DateTime at;
  final Stopwatch clock = Stopwatch()..start();
  final List<(int, String)> events = [];
  _Open(this.source, this.at);
}
