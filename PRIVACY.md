# Kivo — Privacy

*Last updated: 2026-10-01 (Kivo 1.24). The same information is in the app,
under Settings › About › Privacy.*

Kivo has **no ads, no trackers, no analytics and no accounts**. Your videos,
what you watch and how you watch it stay on your phone.

## The only internet connection

To check for updates, Kivo asks this repository's GitHub releases what the
latest version is — once a day if automatic checks are on, or when you ask.
If you accept an update, the APK is downloaded from there. GitHub sees your
IP address, like any website you visit; nothing else is sent.

You can turn the automatic check off in Settings › About.

## Send to TV

When you send a video to a TV, Kivo looks for TVs on your Wi-Fi (an SSDP
search on the local network) and serves the video only to the TV you pick,
at a one-time address that stops working when you finish. None of it leaves
your local network.

## Problem reports

The error log is kept only on your phone. It leaves only if you send it from
Settings › About › Report a problem — by e-mail, as a GitHub issue, or by
copying it — and you see exactly what it contains before it goes.

## No cloud backup

Kivo does not let Android copy its data to your Google account. To move your
settings, playlists and bookmarks to another phone, use Settings › Backup:
you keep the file.

## The Vault

The Vault hides videos from the gallery and from other apps, behind a PIN or
your fingerprint. It does **not** encrypt them — the app says so too.

## Permissions

| Permission | Why |
| --- | --- |
| Videos (`READ_MEDIA_VIDEO`, or storage on older Android) | To show and play your videos. |
| All files (optional) | To delete, rename and use the Vault without asking every time. |
| Notifications | For the background playback and "Send to TV" controls. |
| Install apps | To update itself, only when you accept an update. |
| Fingerprint | To open the Vault, if you turn it on. |
| Wi-Fi state & multicast | To find your TV on the local network. |
| Wake lock, foreground service | To keep playing — or sending to the TV — with the screen off. |
| Internet | Only for the update check and for sending to a TV on your Wi-Fi. |

## Contact

Questions or concerns: open an issue at
<https://github.com/yt-kevincarrera/kivo-player/issues>.
