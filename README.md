# SUDOSEND

**Secure. Local. Instant.** — encrypted file sharing between Android, Windows and Linux on
the same network. No cloud, no accounts, no internet. Built on the
[Wraith Protocol](PROTOCOL.md).

## Features (v0.1 — MVP)

- **Zero-config discovery** over multicast + broadcast, with *Send by IP* as a fallback
- **End-to-end encryption**: X25519 + ChaCha20-Poly1305, fresh keys per transfer
- **MITM-proof first contact**: 6-digit verification code backed by a hash commitment
- **Trusted devices**: verify once, skip the code next time, revoke anytime
- **SHA-256 verification** of every file before it is kept
- **Hardened receiver**: path-traversal-safe names, size enforcement, explicit consent
- **Glassmorphism UI**: frosted glass, animated neon backdrop, live radar; adaptive
  layout (bottom nav on phones, side rail on desktop)

## Setup

Requires Flutter 3.27+ (`flutter doctor` should be green for your targets).

```bash
# Linux / macOS
./setup.sh
# Windows (PowerShell)
./setup.ps1
```

The script runs `flutter create` to generate the native folders (your existing files are
kept), installs packages and runs the test suite. Then:

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
test/            loopback E2E transfer, spoofing and sanitiser tests
```

## Roadmap

- **v0.2**: folders, resume, clipboard sync, QR pairing, `sudosend` CLI for Linux
- **v0.3**: hotspot mode, transfer history, multiple receivers, Rust crypto core

Made by **SUDOSOC**.
