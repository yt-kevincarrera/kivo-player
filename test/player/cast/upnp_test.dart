import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/cast/dlna_network.dart';
import 'package:kivo_player/player/cast/upnp.dart';

const _description = '''<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>[TV] Salón</friendlyName>
    <modelName>UE55</modelName>
    <UDN>uuid:1234</UDN>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>/rc</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>upnp/control/AVTransport1</controlURL>
      </service>
    </serviceList>
  </device>
</root>''';

void main() {
  group('SSDP', () {
    test('a 200 reply gives its headers, keys lower-cased', () {
      final h = parseSsdpResponse(
        'HTTP/1.1 200 OK\r\n'
        'CACHE-CONTROL: max-age=1800\r\n'
        'LOCATION: http://192.168.1.20:9197/dmr\r\n'
        'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n',
      );
      expect(h!['location'], 'http://192.168.1.20:9197/dmr');
    });

    test('a NOTIFY or junk is not a reply', () {
      expect(parseSsdpResponse('NOTIFY * HTTP/1.1\r\nLOCATION: x\r\n'), isNull);
      expect(parseSsdpResponse(''), isNull);
    });

    test('the search asks for media renderers', () {
      final m = ssdpSearch();
      expect(m, startsWith('M-SEARCH * HTTP/1.1\r\n'));
      expect(m, contains('ST: $mediaRendererType'));
      expect(m, endsWith('\r\n\r\n'));
    });
  });

  group('device description', () {
    test(
      'finds the AVTransport control URL, resolved against the location',
      () {
        final r = parseDeviceDescription(
          _description,
          Uri.parse('http://192.168.1.20:9197/dmr/desc.xml'),
        )!;
        expect(r.name, '[TV] Salón');
        expect(r.model, 'UE55');
        expect(r.id, 'uuid:1234');
        expect(
          r.avTransportControl.toString(),
          'http://192.168.1.20:9197/dmr/upnp/control/AVTransport1',
        );
        expect(r.host, '192.168.1.20');
      },
    );

    test('a device without AVTransport cannot play what Kivo sends', () {
      final noAvt = _description.replaceAll('AVTransport', 'ConnectionManager');
      expect(parseDeviceDescription(noAvt, Uri.parse('http://a/')), isNull);
    });

    test('broken XML is skipped, not thrown', () {
      expect(
        parseDeviceDescription('<root><device>', Uri.parse('http://a/')),
        isNull,
      );
    });
  });

  group('SOAP and DIDL', () {
    test('the envelope carries the action, its service and escaped args', () {
      final e = soapEnvelope(avTransportType, 'SetAVTransportURI', {
        'InstanceID': '0',
        'CurrentURI': 'http://x/a?b=1&c=2',
      });
      expect(e, contains('<u:SetAVTransportURI xmlns:u="$avTransportType">'));
      expect(e, contains('<CurrentURI>http://x/a?b=1&amp;c=2</CurrentURI>'));
    });

    test('values and faults are read from replies', () {
      const reply =
          '<s:Envelope xmlns:s="x"><s:Body><u:GetPositionInfoResponse>'
          '<RelTime>0:01:30</RelTime><TrackDuration>1:02:03.500</TrackDuration>'
          '</u:GetPositionInfoResponse></s:Body></s:Envelope>';
      expect(soapValue(reply, 'RelTime'), '0:01:30');
      const fault =
          '<s:Envelope xmlns:s="x"><s:Body><s:Fault><detail><UPnPError>'
          '<errorCode>714</errorCode><errorDescription>Illegal MIME</errorDescription>'
          '</UPnPError></detail></s:Fault></s:Body></s:Envelope>';
      expect(soapFault(fault), 'UPnP 714 Illegal MIME');
    });

    test('DIDL-Lite names the video and how to fetch it', () {
      final d = didlLite(
        title: 'Tom & Jerry <1>',
        url: 'http://192.168.1.5:4000/v/abc.mkv',
        mime: 'video/x-matroska',
        size: 1000,
        duration: const Duration(minutes: 90),
      );
      expect(d, contains('<dc:title>Tom &amp; Jerry &lt;1&gt;</dc:title>'));
      expect(d, contains('protocolInfo="http-get:*:video/x-matroska:'));
      expect(d, contains('size="1000"'));
      expect(d, contains('duration="1:30:00.000"'));
      expect(d, contains('<upnp:class>object.item.videoItem</upnp:class>'));
    });
  });

  group('UPnP time', () {
    test('formats and parses H:MM:SS', () {
      expect(
        formatUpnpTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(formatUpnpTime(const Duration(seconds: 5)), '0:00:05');
      expect(
        parseUpnpTime('1:02:03.250'),
        const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 250),
      );
      expect(parseUpnpTime('NOT_IMPLEMENTED'), isNull);
      expect(parseUpnpTime(''), isNull);
    });

    test('transport states', () {
      expect(tvStateFrom('PLAYING'), TvState.playing);
      expect(tvStateFrom('PAUSED_PLAYBACK'), TvState.paused);
      expect(tvStateFrom('NO_MEDIA_PRESENT'), TvState.stopped);
      expect(tvStateFrom('weird'), TvState.unknown);
    });
  });

  group('local address', () {
    test('the one on the TV\'s subnet wins', () {
      expect(
        pickLocalAddress(['10.0.0.4', '192.168.1.33'], '192.168.1.20'),
        '192.168.1.33',
      );
    });

    test('else a private address; never a public or IPv6 one', () {
      expect(
        pickLocalAddress(['8.8.8.8', '172.20.1.2'], '192.168.9.9'),
        '172.20.1.2',
      );
      expect(pickLocalAddress(['fe80::1', '8.8.8.8'], '192.168.1.20'), isNull);
    });
  });
}
