import 'package:xml/xml.dart';

/// The UPnP pieces of "Enviar a la TV", kept pure (strings in, values out)
/// so they are testable without a network: SSDP replies, device
/// descriptions, SOAP envelopes, DIDL-Lite metadata and UPnP times.

const avTransportType = 'urn:schemas-upnp-org:service:AVTransport:1';
const mediaRendererType = 'urn:schemas-upnp-org:device:MediaRenderer:1';

/// A TV (or any DLNA renderer) found on the Wi-Fi.
class DlnaRenderer {
  /// The device's UDN: stable across searches, so a list refresh keeps rows.
  final String id;
  final String name;
  final String? model;
  final Uri avTransportControl;

  const DlnaRenderer({
    required this.id,
    required this.name,
    required this.avTransportControl,
    this.model,
  });

  String get host => avTransportControl.host;

  @override
  bool operator ==(Object other) => other is DlnaRenderer && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// The headers of an SSDP (HTTP-over-UDP) reply, keys lower-cased; null if
/// it is not a `200 OK` reply.
Map<String, String>? parseSsdpResponse(String datagram) {
  final lines = datagram.split(RegExp(r'\r?\n'));
  if (lines.isEmpty || !lines.first.toUpperCase().startsWith('HTTP/1.1 200')) {
    return null;
  }
  final headers = <String, String>{};
  for (final line in lines.skip(1)) {
    final i = line.indexOf(':');
    if (i <= 0) continue;
    headers[line.substring(0, i).trim().toLowerCase()] = line
        .substring(i + 1)
        .trim();
  }
  return headers;
}

/// The M-SEARCH that asks every renderer on the network to answer.
String ssdpSearch({int mx = 2}) =>
    'M-SEARCH * HTTP/1.1\r\n'
    'HOST: 239.255.255.250:1900\r\n'
    'MAN: "ssdp:discover"\r\n'
    'MX: $mx\r\n'
    'ST: $mediaRendererType\r\n'
    '\r\n';

/// The renderer a device description (fetched from an SSDP `LOCATION`)
/// describes, or null if it has no AVTransport service — then it cannot
/// play what Kivo sends. Embedded devices are searched too: some TVs nest
/// the renderer inside a root device.
DlnaRenderer? parseDeviceDescription(String xml, Uri location) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } catch (_) {
    return null;
  }
  final base = _text(doc.rootElement, 'URLBase');
  final baseUri = base != null && base.isNotEmpty ? Uri.parse(base) : location;
  for (final device in doc.findAllElements('device', namespace: '*')) {
    for (final service in device.findAllElements('service', namespace: '*')) {
      final type = _text(service, 'serviceType') ?? '';
      if (!type.startsWith('urn:schemas-upnp-org:service:AVTransport:')) {
        continue;
      }
      final control = _text(service, 'controlURL');
      if (control == null || control.isEmpty) continue;
      final name = _text(device, 'friendlyName');
      final udn = _text(device, 'UDN') ?? location.toString();
      final model = _text(device, 'modelName');
      return DlnaRenderer(
        id: udn,
        name: (name == null || name.isEmpty) ? location.host : name,
        model: model,
        avTransportControl: baseUri.resolve(control),
      );
    }
  }
  return null;
}

String? _text(XmlElement parent, String tag) {
  for (final child in parent.childElements) {
    if (child.localName == tag) return child.innerText.trim();
  }
  return null;
}

/// A SOAP request body for [action] on [serviceType].
String soapEnvelope(
  String serviceType,
  String action,
  Map<String, String> args,
) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="utf-8"?>')
    ..write(
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">',
    )
    ..write('<s:Body><u:$action xmlns:u="$serviceType">');
  args.forEach((k, v) => b.write('<$k>${xmlEscape(v)}</$k>'));
  b.write('</u:$action></s:Body></s:Envelope>');
  return b.toString();
}

/// A tag's text in a SOAP reply (namespace-agnostic), or null.
String? soapValue(String xml, String tag) {
  try {
    final doc = XmlDocument.parse(xml);
    for (final e in doc.descendants.whereType<XmlElement>()) {
      if (e.localName == tag) return e.innerText.trim();
    }
  } catch (_) {}
  return null;
}

/// The UPnP error a renderer answered with, for the log (`<errorCode>` /
/// `<errorDescription>`), or null.
String? soapFault(String xml) {
  final code = soapValue(xml, 'errorCode');
  if (code == null) return null;
  final desc = soapValue(xml, 'errorDescription');
  return desc == null ? 'UPnP $code' : 'UPnP $code $desc';
}

String xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// DIDL-Lite metadata for the video: most TVs refuse a bare URL, or show it
/// as "Unknown". `protocolInfo` says it is a plain HTTP stream that can be
/// sought by byte range.
String didlLite({
  required String title,
  required String url,
  required String mime,
  int? size,
  Duration? duration,
}) {
  final res = StringBuffer(
    '<res protocolInfo="http-get:*:$mime:'
    'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000"',
  );
  if (size != null && size > 0) res.write(' size="$size"');
  if (duration != null && duration > Duration.zero) {
    res.write(' duration="${formatUpnpTime(duration)}.000"');
  }
  res.write('>${xmlEscape(url)}</res>');
  return '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
      '<item id="kivo" parentID="0" restricted="1">'
      '<dc:title>${xmlEscape(title)}</dc:title>'
      '<upnp:class>object.item.videoItem</upnp:class>'
      '$res'
      '</item></DIDL-Lite>';
}

/// `H:MM:SS` — what AVTransport's Seek takes and GetPositionInfo returns.
String formatUpnpTime(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// Parses `H+:MM:SS[.fff]`; null for `NOT_IMPLEMENTED`, empty or junk.
Duration? parseUpnpTime(String? s) {
  if (s == null) return null;
  final m = RegExp(
    r'^(\d+):(\d{1,2}):(\d{1,2})(?:\.(\d+))?$',
  ).firstMatch(s.trim());
  if (m == null) return null;
  final frac = m.group(4);
  return Duration(
    hours: int.parse(m.group(1)!),
    minutes: int.parse(m.group(2)!),
    seconds: int.parse(m.group(3)!),
    milliseconds: frac == null
        ? 0
        : int.parse(frac.padRight(3, '0').substring(0, 3)),
  );
}

/// The phone's own address the TV can reach: the local IPv4 on the TV's
/// subnet (a /24 match), else the first private IPv4, else null.
String? pickLocalAddress(List<String> localIps, String rendererHost) {
  String prefix(String ip) => ip.substring(0, ip.lastIndexOf('.') + 1);
  final ipv4 = localIps
      .where((ip) => RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(ip))
      .toList();
  for (final ip in ipv4) {
    if (rendererHost.contains('.') && prefix(ip) == prefix(rendererHost)) {
      return ip;
    }
  }
  for (final ip in ipv4) {
    if (ip.startsWith('192.168.') ||
        ip.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip)) {
      return ip;
    }
  }
  return null;
}
