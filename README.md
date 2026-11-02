<p align="center"><img src="assets/icon.png" width="120" alt="SUDOSEND"></p>

<h1 align="center">SUDOSEND</h1>

<p align="center">
  <b>Secure. Local. Instant.</b><br>
  End-to-end encrypted file sharing between Android, Windows, Linux, macOS and iPhone on the same network.<br>
  No cloud · no accounts · no internet · no ads.
</p>

<p align="center">
  <a href="https://github.com/sudosoc/SUDOSEND/releases/latest"><img src="https://img.shields.io/github/v/release/sudosoc/SUDOSEND?label=download&color=22d3ee" alt="latest release"></a>
  <a href="https://github.com/sudosoc/SUDOSEND/actions/workflows/ci.yml"><img src="https://github.com/sudosoc/SUDOSEND/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT"></a>
  <img src="https://img.shields.io/badge/platforms-Android%20%C2%B7%20Windows%20%C2%B7%20Linux%20%C2%B7%20macOS%20%C2%B7%20iOS-8b5cf6" alt="platforms">
</p>

<p align="center">
  <b><a href="https://github.com/sudosoc/SUDOSEND/releases/latest/download/sudosend-android-arm64-v8a.apk">⬇ Android</a></b> ·
  <b><a href="https://github.com/sudosoc/SUDOSEND/releases/latest/download/sudosend-windows-x64-setup.exe">⬇ Windows</a></b> ·
  <b><a href="#linux--kali-debian-ubuntu-raspberry-pi-os">⬇ Linux</a></b> ·
  <b><a href="https://github.com/sudosoc/SUDOSEND/releases/latest/download/sudosend-macos.zip">⬇ macOS</a></b> ·
  <b><a href="https://github.com/sudosoc/SUDOSEND/releases/latest">All downloads</a></b>
</p>

---

## Contents

- [What's new](#whats-new)
- [Features](#features)
- [Install](#install) — [which file?](#which-file-do-i-download) · [Android](#android) · [Windows](#windows) · [Linux](#linux--kali-debian-ubuntu-raspberry-pi-os) · [macOS](#macos) · [iPhone](#iphone--ipad) · [one-line Linux](#one-line-install-linux)
- [Updating](#updating)
- [First transfer](#first-transfer)
- [Where received files go](#where-received-files-go)
- [Command line](#command-line)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Build from source](#build-from-source) · [Releases and signing](#releases-and-signing)
- [Comparison](#comparison) · [Security](#security) · [Roadmap](#roadmap)

---

## What's new

**0.9** — File Metadata Explorer (EXIF, PDF/Office/video properties, security flags) · Smart Recovery
(journaled operations, crash-safe data, trash) · storage map · search across devices with
"get a copy".

**0.8** — Files tab with search, timeline and in-app previews · duplicate detection (SHA-256) ·
device profiles, nicknames, groups and permission profiles · audit log for your SIEM · storage guard ·
statistics with CSV/JSON/PDF reports · smart folders `device/type/date` · photo location stripping ·
Wi-Fi Direct between phones · drag & drop onto a device · in-app updates.
Full notes: [release_notes/](release_notes/).

---

## Features

Every optional feature can be switched off in **Settings → Features**, and each one has an **(i)**
button that explains what it does — in English and Arabic.

### Sharing
- Files of any size, **whole folders** (structure kept), **text** and **clipboard**
- **Resume**: a dropped transfer continues where it stopped; failed sends **retry automatically**
- **Send to several devices at once**, or to a whole **device group** (Personal, Work…)
- **Drag & drop** onto the window, or straight **onto a device** to send to it (desktop)
- Android **share sheet**, desktop **Send to** menu, **hot folders** that send whatever you drop in them
- **Outbox**: queue files for a trusted device that is off — delivered when it comes online
- **Smart compression** for text, code, logs and documents; photos and videos are left alone
- **Previews before accepting**: thumbnails of incoming photos in the request
- **Upload speed limit** so a big transfer doesn't make everyone's video call lag

### Files you receive
- **Smart organization** — `SUDOSEND/<device>/<type>/<date>/file`, automatically (each level optional)
- **Files tab** — search by name, extension, device, date, size and type; **timeline** by day
- **In-app preview** — photos (zoom, swipe), video and audio, PDF, text and code
- **Duplicate detection** with SHA-256 — even when the name is different; keep both or drop the new copy
- **File Metadata Explorer** — EXIF (camera, date taken, GPS with map link), PDF and Office properties,
  video and music info, plus security flags: PDF JavaScript / auto-run, embedded files, Office macros
- **Search across devices** — find a file on every trusted device at once, see each identical copy and
  where it came from, and pull a copy with one tap (no folder paths are ever shared)
- **Storage map** — treemap of space by device, type, day, or real folders on disk
- **Smart Recovery** — journaled file operations, crash-safe app data with automatic backup restore,
  a trash with restore (7/30/90 days), and cleanup of interrupted transfers
- **Storage guard** — warns before the disk fills and refuses transfers that would not fit
- **Statistics** — totals, average and top speed, daily/weekly/monthly activity, top senders and
  types, duplicates, storage — exportable as **CSV, JSON or PDF**

### Devices
- **Device profiles** — system, first and last seen, last address, connection history, transfer history
- **Nicknames** and **groups** (Personal, Work, or your own)
- **Permission profiles** — both ways / receive only / send only, and what each device may do without
  asking (files, messages, clipboard, ring, sync, speed test)
- **Trust that expires** after 1 hour, 1 day, 7 or 30 days
- **Per-device archiving rules** and folder names
- **Auto-reconnect** — trusted devices are found by their last address even where broadcast is blocked

### Between your devices
- 💬 **Messages** — encrypted text threads
- 📋 **Universal clipboard**
- 🔄 **Two-way folder sync** — newest wins, older copies archived, deletions never propagated
- ⚡ **Real speed test** through the encrypted channel
- 🔔 **Find my device** — rings at full volume, even on silent

### No Wi-Fi, no app
- 📡 **Wi-Fi Direct** — two Android phones link directly, both keep their Wi-Fi and data
- 📶 **Hotspot** — Android makes a private network; the other device joins by scanning a QR
- 🌐 **Browser share** — any phone or laptop with a browser can download from you or upload to you;
  links can have a **PIN**, an **expiry** and a **download limit**

### Security
- **End-to-end encryption** — X25519 + ChaCha20-Poly1305, fresh keys for every transfer
- **Verified devices** — 6-digit code backed by a hash commitment, or **QR pairing**; identity keys are pinned
- **Signed proof of delivery** — the receiver's device key signs who sent what, when, and every file's
  SHA-256; anyone can check it offline with `sudosend verify`
- **SHA-256 check** of every file; path-traversal-safe receiver
- **Audit log** — connections refused, requests, transfers, trust changes, deletions, risky files;
  export as CSV or **JSON Lines** for Wazuh / ELK / Splunk
- **Secure file handling** — never opens anything by itself; warns before opening programs, scripts,
  macros and **disguised files** (`invoice.pdf.exe`, a program renamed `.pdf`); Windows
  **Mark-of-the-Web** and macOS **quarantine** on received files
- **Photo privacy** — GPS location (or all metadata) is stripped before sending, without re-compressing
- **Flood protection**, **block list**, **stealth mode**
- Private key kept in **Android Keystore** / **Windows DPAPI**

### App
- **Arabic and English** with full right-to-left layout
- **Glass UI** with three effect levels — *Lite* is automatic on Raspberry Pi and low-end phones
- **Android TV** (remote / D-pad) and a compact layout for small screens
- **In-app updates**
- **CLI** for Linux, Windows and macOS, with pipes and a pairing QR in the terminal

---

## Install

All files are on the **[Releases page](https://github.com/sudosoc/SUDOSEND/releases/latest)**,
each labelled with its system, e.g. **SUDOSEND (Android) — arm64-v8a · most phones**.

### Which file do I download?

| Your device | File | Install |
|---|---|---|
| Android — most phones (64-bit) | [`sudosend-android-arm64-v8a.apk`](https://github.com/sudosoc/SUDOSEND/releases/latest/download/sudosend-android-arm64-v8a.apk) | tap it |
| Android — older 32-bit phones | [`sudosend-android-armeabi-v7a.apk`](https://github.com/sudosoc/SUDOSEND/releases/latest/download/sudosend-android-armeabi-v7a.apk) | tap it |
| Android — emulator / Chromebook | [`sudosend-android-x86_64.apk`](https://github.com/sudosoc/SUDOSEND/releases/latest/download/sudosend-android-x86_64.apk) | tap it |
| Android — not sure / Android TV | [`sudosend-android-universal.apk`](https://github.com/sudosoc/SUDOSEND/releases/latest/download/sudosend-android-universal.apk) | tap it |
| Windows 10 / 11 | [`sudosend-windows-x64-setup.exe`](https://github.com/sudosoc/SUDOSEND/releases/latest/download/sudosend-windows-x64-setup.exe) | double-click |
| Windows, no install | [`sudosend-windows-x64-portable.zip`](https://github.com/sudosoc/SUDOSEND/releases/latest/download/sudosend-windows-x64-portable.zip) | unzip, run `sudosend.exe` |
| Kali / Debian / Ubuntu / Mint — **PC or laptop** | `sudosend_<version>_amd64.deb` | `sudo apt install ./sudosend_*_amd64.deb` |
| Kali / Raspberry Pi OS / Ubuntu — **Raspberry Pi** / ARM64 | `sudosend_<version>_arm64.deb` | `sudo apt install ./sudosend_*_arm64.deb` |
| Fedora / Arch / openSUSE / any Linux | [`x64.tar.gz`](https://github.com/sudosoc/SUDOSEND/releases/latest/download/sudosend-linux-x64.tar.gz) · [`arm64.tar.gz`](https://github.com/sudosoc/SUDOSEND/releases/latest/download/sudosend-linux-arm64.tar.gz) | `./install.sh` |
| Mac, Apple Silicon or Intel (macOS 12+) | [`sudosend-macos.zip`](https://github.com/sudosoc/SUDOSEND/releases/latest/download/sudosend-macos.zip) | unzip, drag to Applications |
| iPhone / iPad | [`sudosend-ios-unsigned.ipa`](https://github.com/sudosoc/SUDOSEND/releases/latest/download/sudosend-ios-unsigned.ipa) | sideload (below) |
| Server / headless | `sudosend-cli-*` | copy and run |

> **Linux: x64 or arm64?** Run `uname -m`. `x86_64` → **x64 / amd64**. `aarch64` → **arm64**
> (every Raspberry Pi 3/4/5 on a 64-bit OS). The wrong one gives `exec format error`.

### Android

1. Download the APK for your phone (almost every phone since 2017 is **arm64-v8a**; unsure → **universal**).
2. Open it. Allow installs from your browser or file manager when Android asks, go back, tap **Install**.
3. Open **SUDOSEND**. Received files go to **Download/SUDOSEND**.

> Play Protect may warn about an unknown developer (the app is not from the Play Store). Choose **Install anyway**.

### Windows

1. Run `sudosend-windows-x64-setup.exe`. If SmartScreen says *Windows protected your PC*,
   click **More info → Run anyway** (the installer is not code-signed yet).
2. Keep the defaults: **Allow through Windows Firewall** (otherwise other devices can't find this PC)
   and **Add `sudosend` to PATH** (command line).
3. Received files go to **Downloads\SUDOSEND**.

### Linux — Kali, Debian, Ubuntu, Raspberry Pi OS

```bash
cd ~/Downloads
sudo apt install ./sudosend_*_arm64.deb     # Raspberry Pi / ARM (aarch64)
# or
sudo apt install ./sudosend_*_amd64.deb     # PC / laptop (x86_64)
```

`apt` installs what SUDOSEND needs (GTK, zenity). Open it from the applications menu or type `sudosend`.
Keep the `./` in front of the file name.

### Linux — any other distro

```bash
tar -xzf sudosend-linux-arm64.tar.gz     # or sudosend-linux-x64.tar.gz
cd sudosend && ./install.sh
```

`install.sh` checks your CPU, installs GTK 3 and zenity if missing (apt / dnf / pacman / zypper),
installs to `~/.local/share/sudosend` (or `/opt/sudosend` with `sudo`), adds the `sudosend` command and a
menu entry, and offers to open the firewall ports. `--yes` answers everything with yes.

### macOS

1. Unzip `sudosend-macos.zip` and drag **SUDOSEND** into *Applications*.
2. Not notarized yet: the first time, **right-click → Open → Open**
   (or `xattr -dr com.apple.quarantine /Applications/SUDOSEND.app`).
3. Allow **local network** access when asked.

### iPhone / iPad

No App Store build yet. Sideload `sudosend-ios-unsigned.ipa` with a free Apple ID using
[AltStore](https://altstore.io) or [Sideloadly](https://sideloadly.io) (refresh every 7 days).
Apple blocks network discovery for unapproved apps, so on iPhone **scan the other device's QR**
(Receive tab) or use **IP / link**. Files are in the **Files** app → *On My iPhone → SUDOSEND*.

### One-line install (Linux)

Detects your CPU and distro, downloads the right file and installs it:

```bash
curl -fsSL https://raw.githubusercontent.com/sudosoc/SUDOSEND/main/get.sh | bash
```

---

## Updating

- **In the app:** Settings → About → **Check for updates**. Android downloads the APK and opens the
  installer, Windows runs the new installer, Linux shows the one-line command. Every download is checked
  against the SHA-256 GitHub publishes. An optional check at startup can be turned off in Features.
- **Command line:** `sudosend update`.

> **Android "App not installed" when updating:** Android only installs an update signed with the same
> key as the installed app. Builds are currently signed with the project's CI key; when the permanent
> release key is introduced, uninstall once and install again. Your received files are not touched.

---

## First transfer

1. Open SUDOSEND on **both** devices, on the **same Wi-Fi or hotspot** (or link two phones with Wi-Fi Direct).
2. On the sender: **Send** tab → **Files**, **Folder** or **Text**.
3. Tap the receiver under **Nearby devices**.
4. Both screens show the same **6-digit code**. Check it on the receiver and tap **Accept**.
   Tick **Trust this device** to skip the code next time.
5. Done — every file is SHA-256 verified before it is saved.

**Faster: QR pairing.** Receiver → **Receive** tab; phone → **Scan QR** on the Send tab. Both devices
now trust each other. If a device doesn't appear, use **IP / link** and type the IP shown on the
receiver's Receive tab.

---

## Where received files go

```
Downloads/SUDOSEND/
├── Galaxy A52/
│   ├── Pictures/2026-11-02/photo1.jpg
│   ├── Documents/2026-11-02/report.pdf
│   ├── Videos/ · Audio/ · Archives/ · Applications/ · Code/
│   ├── Other Files/2026-11-02/unknown.xyz        ← unknown types are never lost
│   └── Folders/2026-11-02/Project/…              ← a sent folder stays whole
├── Laptop/…
└── Browser/…                                     ← uploads from a browser
```

Turn levels on or off in **Settings → Receiving → Organize received files**, or per device
(its folder name, by type, by date) in **Settings → Devices**. Folder sync is never reorganized.

---

## Command line

Installed with the app (`.deb`, `install.sh`, or the Windows installer with *Add to PATH*):

```bash
sudosend                                    # no arguments → opens the app
sudosend receive                            # wait for files, ask before accepting
sudosend receive --yes --trust --once       # unattended, exit after one transfer
sudosend receive --qr                       # pairing QR in the terminal
sudosend receive --organize                 # sort into <device>/<type>/<date>/
sudosend receive --receipts ~/receipts      # keep a signed receipt for every transfer
sudosend send report.pdf photos/ --to laptop        # device name (prefix) …
sudosend send --text "https://…" --to 192.168.1.20  # … IP address …
sudosend send file.iso --to 'sudosend://pair?…'     # … or pairing link
tar c dir | sudosend send - --name dir.tar --to pi   # send from a pipe
sudosend send big.iso --to nas --limit 5M   # cap upload speed
sudosend devices                            # list devices on the network
sudosend id --name Seif-Pi                  # show / rename this device
sudosend verify ~/receipts/*.json           # check receipts offline
sudosend web report.pdf                     # QR + link: any browser can download it
sudosend web --upload                       # let browsers send files to you
sudosend web secret.pdf --pin 4821 --max 1  # PIN-protected, self-destructs after 1 download
sudosend ring --to phone                    # find my phone (trusted devices)
sudosend speedtest --to laptop              # real encrypted throughput
sudosend update                             # is there a newer version?
sudosend --help
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `exec format error` on Linux | Wrong CPU build: `aarch64` → **arm64**, `x86_64` → **x64/amd64**. |
| `sudosend: command not found` after `./install.sh` | Open a new terminal, or `export PATH="$HOME/.local/bin:$PATH"`. |
| Devices don't see each other | Same Wi-Fi? Guest, campus and café Wi-Fi often block device-to-device traffic. Use a hotspot, Wi-Fi Direct, QR or **IP / link**. |
| Linux: others can't find this device | Firewall: `sudo ufw allow 47823/udp && sudo ufw allow 47824:47833/tcp && sudo ufw allow 47840:47849/tcp` (last range: browser share). |
| Windows: others can't find the PC | Re-run the installer with the firewall option; set the Wi-Fi network to *Private*. |
| *Pick files* does nothing on Linux | `sudo apt install zenity` |
| Blank or slow window on a Raspberry Pi | Use a 64-bit OS with a desktop running; *Settings → Appearance → Lite*. Or use the CLI. |
| *Fingerprint mismatch* | Something on the network pretended to be that device. The transfer was blocked on purpose. |
| Android stops mid-transfer | Allow notifications for SUDOSEND; on Xiaomi/Huawei/Samsung set battery to *Unrestricted*. |
| Android: "App not installed" when updating | Different signing key (see [Updating](#updating)). Uninstall once, then install. |
| A transfer was declined automatically | Not enough free space (*Storage guard*), the device is *send only*, or it is blocked — see *Statistics → Audit log*. |
| A received file was deleted right away | *Duplicate files → Remove the new copy* is on, and you already had an identical file. |
| Browser link doesn't open on the other device | Same Wi-Fi/hotspot, and allow TCP 47840–47849 in the firewall. |
| Folder sync doesn't start | Both devices must trust each other and be online; check *Features → Folder sync* and the device's permissions. Not on iOS. |
| Speed test refused | The other device must trust you and allow speed tests. |
| Wi-Fi Direct finds nothing | Wi-Fi ON on both phones, SUDOSEND open on both, *Nearby devices* allowed (Location ON on Android ≤ 12); accept the *Invitation to connect*. |
| Hotspot won't start | Turn off normal tethering, turn on Location (Android ≤ 12), allow *Nearby devices*. |
| A deleted file is needed again | *Settings → Recovery & trash* → **Restore** (kept for the days you chose). |
| Search across devices finds nothing on a device | It must be trusted, online, and allow *Search across devices* (Features) and *Search my files* (its device permissions). |
| No video preview on Windows/Linux | Videos open in your system player there; in-app video is on Android, iOS and macOS. |
| Devices ask for the code again after an update | The device key couldn't be unlocked (OS key store reset) and was recreated — pair again. |

---

## Uninstall

| Installed with | Remove with |
|---|---|
| `.deb` | `sudo apt remove sudosend` |
| `install.sh` | `sudosend --uninstall` |
| Windows installer | *Settings → Apps → SUDOSEND → Uninstall* |
| Android | long-press the icon → *Uninstall* |
| macOS | drag SUDOSEND from Applications to the Trash |

Received files in `Downloads/SUDOSEND` are never deleted.

---

## Build from source

Requires [Flutter](https://docs.flutter.dev/get-started/install) (stable channel).

```bash
git clone https://github.com/sudosoc/SUDOSEND.git && cd SUDOSEND
./setup.sh          # Windows: ./setup.ps1 — platform folders, packages, icons, tests
flutter run -d linux                # or windows, macos, or an Android device id
```

```bash
flutter build apk --release
flutter build linux --release
./tool/build_cli.sh sudosend-cli
./tool/package_linux.sh build/linux/x64/release/bundle sudosend-cli x64   # → dist/*.tar.gz + *.deb
```

CI (`.github/workflows/ci.yml`) runs analysis, the test suite and CLI-to-CLI end-to-end transfers on every
push, and benchmarks the crypto core. Full builds for all platforms run when there is a new version.

### Releases and signing

- **Releasing:** bump `version:` in `pubspec.yaml` and add `release_notes/<version>.md`. CI builds Android,
  Windows, Linux (x64 + ARM64), macOS and iOS and publishes a release with every file labelled by system.
- **Where:** releases are published **in this repository**. If a `RELEASE_TOKEN` secret is set (a
  fine-grained token with *Contents: Read and write* on `sudosoc/SUDOSEND-APP`), they go to that public
  downloads repository instead, so this one can be private. The app and `get.sh` look in both and take
  the newest release, so switching needs no app update.
- **Android signing:** without secrets, APKs are signed with a CI key that is kept between builds, so
  updates install over each other. To use the permanent release key, add these secrets
  (*Settings → Secrets and variables → Actions*):

| Secret | What |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | base64 of the release `.jks` |
| `ANDROID_STORE_PASSWORD` | keystore password |
| `ANDROID_KEY_PASSWORD` | key password |
| `ANDROID_KEY_ALIAS` | key alias |
| `RELEASE_TOKEN` *(optional)* | publish to `sudosoc/SUDOSEND-APP` instead of here |

### Performance

The optimised ChaCha20-Poly1305 does ~100–110 MB/s per core on a 2-vCPU cloud runner (4–5× a pure-Dart
cipher), spread over worker isolates; SHA-256 of large files runs on its own isolate. Real transfers
are usually limited by Wi-Fi, not the CPU.

### Layout

```
lib/
  app/                  strings (EN/AR), scope
  state/                AppController, settings, history, library (files index), devices,
                        audit log, stats, chat, outbox, previews, updater
  platform/             Android bridge, desktop helpers (open, notify, single instance)
  ui/                   tabs (send, receive, files, transfers, messages), preview, dashboard,
                        devices, audit, settings, Wi-Fi Direct, sync, glass widgets
android/…/kotlin/       engine, foreground service, notifications, share, Keystore, hotspot,
                        Wi-Fi Direct, ringer, disk space
packages/wraith_core/   pure-Dart core, shared by the app and the CLI
  wraith.dart             framing, handshake, pipelined secure channel
  chacha_poly.dart        optimised RFC 8439 ChaCha20-Poly1305 · aead.dart  engines
  transfer.dart           sender/receiver (resume, folders, text, compression, sync, speed test)
  discovery.dart          UDP announce / probe / unicast reconnect
  organize.dart           device/type/date placement · metadata.dart  photo scrubbing
  inspect.dart            metadata explorer (EXIF, PDF, OOXML, MP4, ID3) · journal.dart  recovery journal
  risk.dart               risky / disguised file detection · disk.dart  free space
  sync.dart · receipt.dart · pairing.dart · identity.dart · web_share.dart · vault_windows.dart
  bin/sudosend.dart       command-line client
packaging/              Linux install.sh, Windows Inno Setup script
tool/                   bootstrap, packaging, signing, release, CI helpers
test/                   RFC 8439 vectors, loopback end-to-end tests, organization, metadata,
                        risk, library, devices, audit, stats, translations
```

---

## Comparison

| | SUDOSEND | LocalSend | KDE Connect | Quick Share |
|---|:-:|:-:|:-:|:-:|
| Android · Windows · Linux · macOS · iOS | ✅ | ✅ | ⚠️ iOS limited | ❌ no Linux / iOS |
| No internet, no account | ✅ | ✅ | ✅ | ⚠️ |
| Verify the other device (code or QR) | ✅ | — | ✅ pairing | ✅ |
| **Signed proof of delivery**, verifiable offline | ✅ | — | — | — |
| SHA-256 check of every file | ✅ | — | — | — |
| Resume interrupted transfers | ✅ | — | — | — |
| Duplicate detection | ✅ | — | — | — |
| Metadata explorer (EXIF, PDF, Office, video) | ✅ | — | — | — |
| Search files across devices | ✅ | — | — | — |
| Trash + crash recovery | ✅ | — | — | — |
| Search, timeline and in-app preview of received files | ✅ | — | — | — |
| Automatic device/type/date folders | ✅ | — | — | — |
| Per-device permission profiles, expiring trust | ✅ | — | ⚠️ per plugin | — |
| Audit log (CSV / JSON Lines) | ✅ | — | — | — |
| Risky / disguised file warnings | ✅ | — | — | — |
| Photo location stripping | ✅ | — | — | — |
| Flood protection + block list | ✅ | — | — | — |
| CLI with pipes and terminal QR | ✅ | — | ⚠️ `kdeconnect-cli` | — |
| Universal clipboard | ✅ | — | ✅ | — |
| Send to / receive from a plain browser | ✅ | ✅ send only | — | — |
| Hotspot / Wi-Fi Direct without a router | ✅ Android | — | — | ✅ |
| PIN-protected, self-destructing links | ✅ | — | — | — |
| Outbox for offline devices | ✅ | — | — | — |
| Two-way folder sync | ✅ | — | — | — |
| Encrypted messages | ✅ | — | ⚠️ SMS relay | — |
| Find my device | ✅ | — | ✅ | — |
| Built-in speed test, compression, speed limit | ✅ | — | — | — |
| Android TV with remote | ✅ | ⚠️ | — | — |
| Arabic UI with RTL | ✅ | ✅ | ✅ | ✅ |

*✅ yes · ⚠️ partly · ❌ no · — not offered or not documented. Based on each project's public
documentation as of late 2026 — corrections welcome via an issue.*

## Security

Wire protocol, threat model and design decisions: **[PROTOCOL.md](PROTOCOL.md)**.
X25519 ephemeral keys + Ed25519 identities, hash-committed handshake with a 6-digit SAS,
ChaCha20-Poly1305 with counter nonces, and SHA-256 on every file.
Found a vulnerability? Please email **ceo@sudosoc.com** rather than opening a public issue.

## Roadmap

- Permanent Android release key and signed / notarized desktop builds
- Folder sync on iOS (security-scoped bookmarks)
- Play Store and App Store builds

## License

[MIT](LICENSE) © SUDOSOC. Bundled font: IBM Plex Sans Arabic (SIL OFL 1.1).

<p align="center">Made by <b>Seif Alsayed Ali · SUDOSOC</b> — <a href="https://seif.sudosoc.com">seif.sudosoc.com</a></p>
