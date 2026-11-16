import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as mpv;
import 'video_progress.dart';

/// Samples the existing player through its own libmpv client, off the UI
/// isolate. A core-lock wait during decoding/seeking cannot freeze Flutter.
/// Never consumes media_kit's event queue or creates another decoder/player.
class NativeVideoProbe {
  NativeVideoProbe({required this.library, required this.handle});
  final String library;
  final int handle;
  final _events = StreamController<VideoProgress>.broadcast();
  final _messages = ReceivePort();
  final _ready = Completer<void>();
  final _done = Completer<void>();
  SendPort? _commands;
  int _epoch = 0;
  bool _disposed = false;
  Stream<VideoProgress> get stream => _events.stream;

  Future<void> start() async {
    _messages.listen((message) {
      if (message is SendPort) {
        _commands = message;
        message.send(_disposed ? 'stop' : _epoch);
        if (!_ready.isCompleted) _ready.complete();
      } else if (message is String) {
        if (message == 'done') {
          if (!_ready.isCompleted) {
            _ready.completeError(StateError('Video probe unavailable'));
          }
          if (!_done.isCompleted) _done.complete();
          _messages.close();
        }
      } else if (!_disposed && message is List && message[0] == _epoch) {
        _events.add(
          VideoProgress(
            position: message[1] == null
                ? null
                : Duration(microseconds: message[1] as int),
            videoPosition: message[2] == null
                ? null
                : Duration(microseconds: message[2] as int),
            paused: message[3] as bool,
            seeking: message[4] as bool,
            sampledAt: Duration(microseconds: message[5] as int),
          ),
        );
      }
    });
    await Isolate.spawn(_runProbe, (library, handle, _messages.sendPort));
    await _ready.future.timeout(const Duration(seconds: 3));
  }

  /// Invalidates queued samples before a new loadfile starts.
  void beginSession() {
    _commands?.send(++_epoch);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _commands?.send('stop');
    // A late startup handshake also sees _disposed and requests shutdown.
    await _done.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    await _events.close();
  }
}

Future<void> _runProbe((String, int, SendPort) configuration) async {
  try {
    await _runAttachedProbe(configuration);
  } catch (_) {
    // Loading a library or creating a monitor is optional; never strand the
    // opening player waiting for a worker that has already exited.
    configuration.$3.send('done');
  }
}

Future<void> _runAttachedProbe((String, int, SendPort) configuration) async {
  final (library, handle, output) = configuration;
  final api = mpv.MPV(DynamicLibrary.open(library));
  final name = 'kivo-video-health'.toNativeUtf8();
  final client = api.mpv_create_client(
    Pointer<mpv.mpv_handle>.fromAddress(handle),
    name.cast(),
  );
  calloc.free(name);
  if (client == nullptr) {
    output.send('done');
    return;
  }
  final commands = ReceivePort();
  var stopped = false;
  var epoch = 0;
  commands.listen((message) {
    if (message == 'stop') {
      stopped = true;
    } else if (message is int) {
      epoch = message;
    }
  });
  output.send(commands.sendPort);
  // mpv 0.36 time-pos follows video while it is playing; audio-pts is
  // independent. There is no public video-pts property in this version.
  final names = [
    'audio-pts',
    'time-pos',
    'pause',
    'seeking',
  ].map((s) => s.toNativeUtf8()).toList();
  final number = calloc<Double>();
  final flag = calloc<Int32>();
  final clock = Stopwatch()..start();
  int? time(int i) {
    final status = api.mpv_get_property(
      client,
      names[i].cast(),
      mpv.mpv_format.MPV_FORMAT_DOUBLE,
      number.cast(),
    );
    return status >= 0 && number.value.isFinite
        ? (number.value * 1000000).round()
        : null;
  }

  bool boolean(int i) =>
      api.mpv_get_property(
            client,
            names[i].cast(),
            mpv.mpv_format.MPV_FORMAT_FLAG,
            flag.cast(),
          ) >=
          0 &&
      flag.value != 0;
  try {
    while (!stopped) {
      // A separate client has a separate event queue. Drain it without waiting;
      // shutdown must be acknowledged before media_kit disposes the core.
      for (var i = 0; i < 100; i++) {
        final event = api.mpv_wait_event(client, 0).ref.event_id;
        if (event == mpv.mpv_event_id.MPV_EVENT_NONE) break;
        if (event == mpv.mpv_event_id.MPV_EVENT_SHUTDOWN) {
          stopped = true;
          break;
        }
      }
      if (stopped) break;
      final position = time(0);
      final picture = time(1);
      final paused = boolean(2);
      final seeking = boolean(3);
      output.send([
        epoch,
        position,
        picture,
        paused,
        seeking,
        clock.elapsedMicroseconds,
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  } finally {
    commands.close();
    for (final name in names) {
      calloc.free(name);
    }
    calloc.free(number);
    calloc.free(flag);
    api.mpv_destroy(client);
    output.send('done');
  }
}
