# SUDOSEND

[![CI](https://github.com/sudosoc/SUDOSEND/actions/workflows/ci.yml/badge.svg)](https://github.com/sudosoc/SUDOSEND/actions/workflows/ci.yml)

**Secure. Local. Instant.** — encrypted file sharing between Android, Windows and Linux on
the same network. No cloud, no accounts, no internet. Built on the
[Wraith Protocol](PROTOCOL.md).

## Features (v0.2)

- **Zero-config discovery** over multicast + broadcast, with *Send by IP* as a fallback
- **Files, whole folders, and text/clipboard** — folder structure is preserved
- **Resume**: a dropped transfer continues where it stopped, re-verified end to end
- **End-to-end encryption**: X25519 + ChaCha20-Poly1305, fresh keys per transfer
- **MITM-proof first contact**: 6-digit verification code backed by a hash commitment
- **Trusted devices**: verify once, skip the code next time, revoke anytime
- **SHA-256 verification** of every file before it is kept
- **Hardened receiver**: path-traversal-safe names, size enforcement, explicit consent
- **Glassmorphism UI**: frosted glass, animated neon backdrop, live radar; adaptive
  layout (bottom nav on phones, side rail on desktop)
- **CLI** for Linux and Windows, fully interoperable with the app

## Download

Grab the latest build from **Releases**: `sudosend-android.apk`,
`sudosend-windows-x64.zip`, `sudosend-linux-x64.tar.gz`, plus standalone CLI binaries.
Every push to `main` also builds all of them as CI artifacts.

## CLI

```bash
sudosend receive                       # wait for files (asks before accepting)
sudosend receive --yes --trust --once  # unattended
sudosend send report.pdf photos/ --to laptop
sudosend send --text "https://…" --to 192.168.1.20
sudosend devices
sudosend id --name Seif-Arch
```

Run from source with `dart run bin/sudosend.dart …`, or build a native binary with
`dart compile exe bin/sudosend.dart -o sudosend`.

## Setup

Requires Flutter 3.27+ (`flutter doctor` should be green for your targets).

```bash
# Linux / macOS
./setup.sh
# Windows (PowerShell)
./setup.ps1
```

The script generates the native folders (your existing files are kept), brands the window
titles, installs packages, generates the launcher icons and runs the test suite. Then:

```bash
flutter run -d linux      # or windows, or an Android device id
flutter build apk --release
flutter build linux --release
flutter build windows --release
```

### Platform notes

- **Linux**: the file picker needs `zenity` or `kdialog`. Open the ports if you use a
  firewall: `sudo ufw allow 47823/udp && sudo ufw allow 47824/tcp`.
- **Windows**: allow SUDOSEND on *Private networks* when the firewall prompt appears.
- **Android**: files land in `Download/SUDOSEND`. On Android 9 and below, or if that folder
  is not writable, they go to the app's documents folder (shown on the Receive tab).
- Guest / campus Wi-Fi often has *client isolation*, which blocks all device-to-device
  traffic. Use a phone hotspot in that case.

## Layout

```
lib/
  core/          protocol, crypto, discovery, transfer engine (no UI)
    wraith.dart       framing, handshake, secure channel
    discovery.dart    UDP announce/listen
    transfer.dart     sender + receiver state machines
    identity.dart     Ed25519 identity + trust store
  state/         AppController (ChangeNotifier)
  ui/            glass widgets, radar, tabs, dialogs
bin/sudosend.dart  command-line client
tool/            bootstrap + icon generator
test/            loopback E2E: transfer, resume, tamper, folders, text, spoofing
```

## Roadmap

- **v0.3**: QR pairing, Android share-sheet target, persistent transfer history
- **v0.4**: hotspot mode, multiple receivers, native (Rust) crypto core

Made by **SUDOSOC**.
