# Kivo send to TV (tanda 8) — Design

**Date:** 2026-10-01
**Decision (user):** DLNA/UPnP, not Google Cast — open, no proprietary SDK
(keeps Kivo clean for IzzyOnDroid), works with most smart TVs. Chromecast-only
devices are out of reach without a DLNA app; accepted.

## How it works

1. **Find TVs** (`SsdpTvDiscovery`): an SSDP `M-SEARCH` for
   `MediaRenderer:1` to 239.255.255.250:1900 (sent three times — UDP is lossy
   and TVs on Wi-Fi doze), for 5 s, holding Android's multicast lock. Each
   reply's `LOCATION` description is fetched; a device with an AVTransport
   service is a TV Kivo can use (embedded devices included; `URLBase`
   honoured).
2. **Serve the video** (`CastBridge.kt` → `CastHttpServer`): a minimal
   HTTP/1.1 server in Kotlin — GET/HEAD, `Range: bytes=` (seeking), DLNA's
   `transferMode` / `contentFeatures` headers — streaming straight from the
   ContentResolver (`content://`) or a file path (Vault, picker). Native, not
   Dart: reading a `content://` uri needs the ContentResolver, and the
   alternative (Dart reopening a descriptor through `/proc/self/fd`) is not
   something that can be relied on across devices. The one published path
   carries a random 128-bit token; everything else is a 404; the server stops
   with the cast.
3. **Drive the TV** (`SoapTvTransport`): `SetAVTransportURI` with DIDL-Lite
   metadata (title, mime, size, duration — many TVs refuse a bare URL),
   `Play`, then `Seek` to where the phone was once the TV reports it is
   playing (many refuse a seek before). The URL uses the phone's address on
   the TV's subnet (`pickLocalAddress`).
4. **Mirror it** (`CastController`): `GetPositionInfo` + `GetTransportInfo`
   once a second. Stopped after having played → the film ended (or the TV's
   remote stopped it): the cast ends and the phone carries on from there.
   Five unanswered polls in a row → the TV is gone: same, with a "lost
   connection" message. One dropped reply is just Wi-Fi.
5. **Keep alive** (`CastService`): a mediaPlayback foreground service with
   "Reproduciendo en Salón" and a "Dejar de enviar" action, plus a partial
   wake lock (6 h ceiling) and a high-perf Wi-Fi lock, so the stream survives
   the screen turning off.

## Robustness

- Every start bumps a generation; a stop half-way through connecting (the
  button is there while connecting) makes everything still in flight for it
  a no-op — no half-started cast, no stray notification.
- The foreground service starts first, while the app is surely in the
  foreground (Android 12+ refuses it from the background, and connecting can
  take long enough for the screen to go off).
- Each SOAP exchange is bounded end to end (8 s); polls never overlap; the
  transport's HTTP client is closed with the cast.
- Another video opened anywhere (not only in the player) ends the cast; keys
  drive the TV only while the visible video is the one being cast.
- Server: a stop closes the streams in progress; an unknown size
  (`statSize` -1, provider without `SIZE`) is served whole without ranges;
  the start offset is reached before answering (a short `skip` never sends
  wrong bytes under a correct Content-Range).
- The notification's stop also hands the TV's position back to the phone.

## In the player

- **Button:** in the top bar where there is room (width ≥ 560: landscape,
  tablets); in portrait, where the bar would squeeze the title to nothing,
  it is a row in the More menu instead (`kCastInBarMinWidth`: always in
  exactly one place).
- **Picker sheet:** TVs as they answer; while searching a spinner; nothing
  found → how to fix it (same Wi-Fi, TV on, DLNA / "Compartir pantalla"
  enabled) + "Buscar de nuevo". A note: works with most smart TVs, the video
  goes over the Wi-Fi only, subtitles are not sent.
- **Cast screen** (over the player, for the video being cast): "Reproduciendo
  en Salón", the TV's position on a bar, play/pause, skips, and "Dejar de
  enviar" — which stops the TV and leaves the phone paused at the TV's
  position. The phone stays paused while casting (anything that starts it is
  paused again). Opening another video ends the cast. Keyboard/remote keys
  drive the TV while casting; the D-pad moves between the cast screen's
  buttons (first press: "Dejar de enviar") and never into the covered
  player controls.
- A TV that refuses the video: **KV-505** "No pudimos enviar el video a la
  TV", logged with the UPnP fault.

## Privacy

The privacy page now says it: casting looks for TVs on the local network and
serves the video only to the chosen TV, at a one-time address, never over
the internet. "La única conexión" became "La única conexión a Internet";
permissions list Wi-Fi.

New permissions: `CHANGE_WIFI_MULTICAST_STATE`, `ACCESS_WIFI_STATE`,
`WAKE_LOCK` (all normal, no prompt).

## Not in this tanda

- Subtitles on the TV (DLNA has no standard; Samsung's `CaptionInfo.sec` and
  similar are vendor-specific) — said in the picker.
- Queue / autoplay on the TV (the cast ends with the video).
- Transcoding: the TV must play the file's format itself; most play
  MP4/MKV/H.264, many HEVC.

## Testing

Pure UPnP (SSDP replies, descriptions, SOAP, faults, DIDL, times, address
choice); the controller against a fake TV and platform (serve → URL →
setUri/play, resume seek, refusal = KV-505 with nothing left running, stop,
notification stop, remote controls with clamping, end of film, lost TV); the
picker and the cast screen. The Kotlin server is compiled by the release
build; it is not exercised on a device by the tests.
