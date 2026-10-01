import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'upnp.dart';

/// What the TV says it is doing (AVTransport's TransportState).
enum TvState { playing, paused, stopped, transitioning, unknown }

TvState tvStateFrom(String? s) => switch (s) {
  'PLAYING' => TvState.playing,
  'PAUSED_PLAYBACK' || 'PAUSED_RECORDING' => TvState.paused,
  'STOPPED' || 'NO_MEDIA_PRESENT' => TvState.stopped,
  'TRANSITIONING' => TvState.transitioning,
  _ => TvState.unknown,
};

/// Drives one renderer's AVTransport. An interface so the cast controller
/// can be tested without a TV.
abstract class TvTransport {
  Future<void> setUri(String url, String metadata);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration to);

  /// (position, duration) — either may be null when the TV does not say.
  Future<(Duration?, Duration?)> position();
  Future<TvState> state();

  /// Releases the connection; the transport is not used after this.
  void close();
}

class UpnpCallException implements Exception {
  final String action;
  final String detail;
  UpnpCallException(this.action, this.detail);
  @override
  String toString() => 'UpnpCallException($action: $detail)';
}

/// [TvTransport] over SOAP/HTTP.
class SoapTvTransport implements TvTransport {
  final Uri control;
  final HttpClient _http;
  SoapTvTransport(this.control, {HttpClient? http})
    : _http =
          http ??
          (HttpClient()..connectionTimeout = const Duration(seconds: 4));

  @override
  void close() => _http.close(force: true);

  /// The whole exchange — connect, send, reply, body — is bounded: a TV
  /// that stalls half-way through a reply must not hang the cast.
  Future<String> _call(
    String action, [
    Map<String, String> args = const {},
  ]) =>
      _exchange(action, args).timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw UpnpCallException(action, 'timeout'),
      );

  Future<String> _exchange(String action, Map<String, String> args) async {
    final body = utf8.encode(
      soapEnvelope(avTransportType, action, {'InstanceID': '0', ...args}),
    );
    try {
      final req = await _http.postUrl(control);
      req.headers
        ..set(HttpHeaders.contentTypeHeader, 'text/xml; charset="utf-8"')
        ..set('SOAPACTION', '"$avTransportType#$action"');
      req.contentLength = body.length;
      req.add(body);
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw UpnpCallException(
          action,
          soapFault(text) ?? 'HTTP ${res.statusCode}',
        );
      }
      return text;
    } on UpnpCallException {
      rethrow;
    } catch (e) {
      throw UpnpCallException(action, '$e');
    }
  }

  @override
  Future<void> setUri(String url, String metadata) => _call(
    'SetAVTransportURI',
    {'CurrentURI': url, 'CurrentURIMetaData': metadata},
  );

  @override
  Future<void> play() => _call('Play', {'Speed': '1'});

  @override
  Future<void> pause() => _call('Pause');

  @override
  Future<void> stop() => _call('Stop');

  @override
  Future<void> seek(Duration to) =>
      _call('Seek', {'Unit': 'REL_TIME', 'Target': formatUpnpTime(to)});

  @override
  Future<(Duration?, Duration?)> position() async {
    final xml = await _call('GetPositionInfo');
    return (
      parseUpnpTime(soapValue(xml, 'RelTime')),
      parseUpnpTime(soapValue(xml, 'TrackDuration')),
    );
  }

  @override
  Future<TvState> state() async => tvStateFrom(
    soapValue(await _call('GetTransportInfo'), 'CurrentTransportState'),
  );
}

/// Finds renderers on the Wi-Fi. An interface for tests.
abstract class TvDiscovery {
  /// Emits the growing list of renderers found, and completes after
  /// [timeout].
  Stream<List<DlnaRenderer>> search({Duration timeout});
}

/// SSDP over UDP multicast, then each reply's device description over HTTP.
class SsdpTvDiscovery implements TvDiscovery {
  @override
  Stream<List<DlnaRenderer>> search({
    Duration timeout = const Duration(seconds: 5),
  }) {
    final out = StreamController<List<DlnaRenderer>>();
    final found = <String, DlnaRenderer>{};
    final asked = <String>{};
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    RawDatagramSocket? socket;
    Timer? resend;
    Timer? end;

    Future<void> describe(String location) async {
      try {
        final uri = Uri.parse(location);
        final req = await http.getUrl(uri);
        final res = await req.close().timeout(const Duration(seconds: 4));
        final xml = await res.transform(utf8.decoder).join();
        final r = parseDeviceDescription(xml, uri);
        if (r != null && !out.isClosed && !found.containsKey(r.id)) {
          found[r.id] = r;
          out.add(
            found.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
          );
        }
      } catch (_) {
        // A device that does not answer its own description is skipped.
      }
    }

    Future<void> run() async {
      try {
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        socket!.listen((event) {
          if (event != RawSocketEvent.read) return;
          final d = socket!.receive();
          if (d == null) return;
          final headers = parseSsdpResponse(
            latin1.decode(d.data, allowInvalid: true),
          );
          final location = headers?['location'];
          if (location == null || !asked.add(location)) return;
          describe(location);
        });
        final msg = latin1.encode(ssdpSearch());
        final group = InternetAddress('239.255.255.250');
        void send() => socket?.send(msg, group, 1900);
        send();
        // UDP is lossy and TVs asleep on Wi-Fi miss the first one.
        var sent = 1;
        resend = Timer.periodic(const Duration(milliseconds: 800), (t) {
          send();
          if (++sent >= 3) t.cancel();
        });
      } catch (e) {
        if (!out.isClosed) out.addError(e);
      }
      end = Timer(timeout, () async {
        resend?.cancel();
        socket?.close();
        http.close(force: true);
        if (!out.isClosed) {
          if (found.isEmpty) out.add(const []);
          await out.close();
        }
      });
    }

    out.onListen = run;
    out.onCancel = () {
      resend?.cancel();
      end?.cancel();
      socket?.close();
      http.close(force: true);
    };
    return out.stream;
  }
}

/// The phone's IPv4 addresses (for the URL the TV fetches from).
Future<List<String>> localIpv4s() async {
  try {
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final i in ifaces)
        for (final a in i.addresses)
          if (!a.isLoopback) a.address,
    ];
  } catch (_) {
    return const [];
  }
}
