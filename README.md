<p align="center"><img src="assets/icon.png" width="120" alt="SUDOSEND"></p>

<h1 align="center">SUDOSEND</h1>

<p align="center">
  <b>Secure. Local. Instant.</b><br>
  Encrypted file sharing between Android, Windows, Linux, macOS and iPhone on the same network.<br>
  No cloud · no accounts · no internet.
</p>

<p align="center">
  <a href="https://github.com/sudosoc/SUDOSEND/actions/workflows/ci.yml"><img src="https://github.com/sudosoc/SUDOSEND/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/sudosoc/SUDOSEND/releases/latest"><img src="https://img.shields.io/github/v/release/sudosoc/SUDOSEND?label=release" alt="release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT"></a>
</p>

---

## Contents

- [Features](#features)
- [Install](#install)
  - [Which file do I download?](#which-file-do-i-download)
  - [Android](#android)
  - [Windows](#windows)
  - [Linux — Kali, Debian, Ubuntu, Raspberry Pi OS](#linux--kali-debian-ubuntu-raspberry-pi-os)
  - [Linux — any other distro](#linux--any-other-distro)
  - [macOS](#macos)
  - [iPhone / iPad](#iphone--ipad)
  - [One-line install (Linux)](#one-line-install-linux)
- [First transfer](#first-transfer)
- [Command line](#command-line)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Build from source](#build-from-source)
- [Security](#security)

---

## Features

**Sharing**
- Files of any size, **whole folders** (structure kept), and **text / clipboard**
- **Share sheet** on Android: *Share → SUDOSEND* from any app
- **Drag & drop** and right-click **Send to** on desktop
- **Resume**: a dropped transfer continues where it stopped
- **Background transfers** on Android: keeps going with the screen off or the app closed, with progress in a notification; optional *receive in the background*
- **Notifications** with Accept / Decline right from the notification
- **History** of every transfer, with *Open* and *Show in folder*

**Paid elsewhere — free here**
- 📋 **Universal clipboard** — copy on one device, paste on your others (Pushbullet charges for this)
- 🌐 **Share with any browser** — send to *and receive from* a device that doesn't have the app,
  even an iPhone: it scans a QR and gets a download/upload page (Send Anywhere / Feem-style)
- 📶 **No Wi-Fi? Make one** — Android creates a private hotspot; the other phone joins by scanning a QR
- 🔒 **Protected, self-destructing links** — PIN, expiry (10 min – 2 h), one-download links (WeTransfer Pro / Send Anywhere Plus)
- 📬 **Outbox** — send to a trusted device that's switched off; it's delivered the moment it comes online,
  and dropped connections **retry and resume automatically**
- 📂 **Hot folders** (desktop) — drop anything into `SUDOSEND Outbox/<device>/` and it's sent by itself (Resilio-style)
- 🔔 **Find my device** — make your phone ring at full volume, even on silent (AirDroid Premium)
- 🚦 **Upload speed limit** and 📊 **per-device data usage**
- 🧾 Signed delivery receipts, multi-device send, no file-size limits, no ads, no account

**Only in SUDOSEND**
- **Signed proof of delivery** — every transfer ends with a receipt the *receiver's device key* signs:
  who sent what to whom, when, and the SHA-256 of every file. Export it and anyone can check it
  offline with `sudosend verify receipt.json`. Built for evidence handling, audits and "I never got it" disputes.
- **Send to several devices at once** — select devices, one tap
- **Pipe anything from the terminal** — `tar c project | sudosend send - --name project.tar --to laptop`
- **Received links open with one tap**, received text can go **straight to the clipboard**
- **A folder per sender** and a **JSON transfer log** export

**Security**
- **End-to-end encryption**: X25519 + ChaCha20-Poly1305, fresh keys per transfer
- **QR pairing**: scan once → both devices trust each other, no code to compare
- **MITM-proof first contact** otherwise: 6-digit code backed by a hash commitment
- **Trusted / blocked devices**, **auto-accept** for trusted ones
- **Flood protection**: connection rate limits per IP, one prompt per device, block list
- **Private key in the OS key store** (Android Keystore, Windows DPAPI)
- **Stealth mode**: stop announcing yourself; reachable only by QR or IP
- **SHA-256 verification** of every file; path-traversal-safe receiver

**App**
- **Arabic and English**, full right-to-left layout
- **Glassmorphism UI** with three effect levels — *Balanced* (default) keeps the glass look
  without live blur, *Lite* is automatic on Raspberry Pi and low-end phones
- **CLI** for Linux, Windows and macOS — prints a pairing QR right in the terminal

---

## Install

All files are on the **[Releases page](https://github.com/sudosoc/SUDOSEND/releases/latest)** —
each one is labelled with its system in parentheses, e.g. **SUDOSEND (Android) — arm64-v8a**.

### Which file do I download?

| Your device | Download | Install with |
|---|---|---|
| Android — most phones (64-bit) | `sudosend-android-arm64-v8a.apk` | tap it |
| Android — older 32-bit phones | `sudosend-android-armeabi-v7a.apk` | tap it |
| Android — emulator / Chromebook | `sudosend-android-x86_64.apk` | tap it |
| Android — not sure | `sudosend-android-universal.apk` (works everywhere, bigger) | tap it |
| Windows 10 / 11 | `sudosend-windows-x64-setup.exe` | double-click |
| Windows (no install) | `sudosend-windows-x64-portable.zip` | unzip, run `sudosend.exe` |
| Kali / Debian / Ubuntu / Mint on a **PC or laptop** | `sudosend_<version>_amd64.deb` | `sudo apt install ./sudosend_*_amd64.deb` |
| Kali / Raspberry Pi OS / Ubuntu on a **Raspberry Pi** or other ARM board | `sudosend_<version>_arm64.deb` | `sudo apt install ./sudosend_*_arm64.deb` |
| Fedora / Arch / openSUSE / other Linux | `sudosend-linux-x64.tar.gz` or `sudosend-linux-arm64.tar.gz` | `./install.sh` |
| Mac (Apple Silicon or Intel) | `sudosend-macos.zip` | unzip, drag to Applications |
| iPhone / iPad | `sudosend-ios-unsigned.ipa` | sideload (see below) |

> **Linux: x64 or arm64?** Run `uname -m`.
> `x86_64` → **x64 / amd64**. `aarch64` → **arm64** (every Raspberry Pi 3/4/5 running a 64-bit OS).
> Running the wrong one gives `exec format error`.

### Android

1. Download the APK for your phone's CPU (almost every phone from 2017 on is **arm64-v8a**;
   check *Settings → About phone*, or a CPU-info app — if unsure take **universal**).
2. Open it. Android asks to allow installs from this source (your browser or file manager). Allow it, go back, and tap **Install**.
3. Open **SUDOSEND**. Received files are saved in **Download/SUDOSEND**.

> Play Protect may warn about an unknown developer, because the APK is not from the Play Store. Choose **Install anyway**.

### Windows

1. Download `sudosend-windows-x64-setup.exe` and run it.
2. If SmartScreen shows *Windows protected your PC*, click **More info → Run anyway** (the installer is not code-signed yet).
3. Keep the default options:
   - **Allow SUDOSEND through Windows Firewall** opens the network ports for you. Without it, other devices can't find this PC.
   - **Add `sudosend` to PATH** enables the command-line tool in any terminal.
4. Launch SUDOSEND from the Start menu.

Received files go to **Downloads\SUDOSEND**.

### Linux — Kali, Debian, Ubuntu, Raspberry Pi OS

Check your CPU with `uname -m`, download the matching `.deb`, then:

```bash
cd ~/Downloads
sudo apt install ./sudosend_*_arm64.deb     # Raspberry Pi / ARM (aarch64)
# or
sudo apt install ./sudosend_*_amd64.deb     # PC / laptop (x86_64)
```

`apt` installs everything SUDOSEND needs (GTK, zenity) automatically. Then:

- Open **SUDOSEND** from the applications menu (*Internet* / *Network* category), **or**
- type `sudosend` in a terminal.

> Keep the `./` in front of the file name. Without it, apt searches its repositories instead of the local file.

### Linux — any other distro

```bash
cd ~/Downloads
tar -xzf sudosend-linux-arm64.tar.gz     # or sudosend-linux-x64.tar.gz
cd sudosend
./install.sh
```

The installer does everything for you:

1. checks the file matches your CPU,
2. installs GTK 3 and zenity if missing (apt / dnf / pacman / zypper),
3. installs SUDOSEND to `~/.local/share/sudosend`. Use `sudo ./install.sh` to install to `/opt/sudosend` for every user,
4. creates the `sudosend` command and an applications-menu entry,
5. adds `~/.local/bin` to your PATH if needed,
6. offers to open the firewall ports if `ufw` or `firewalld` is active.

Add `--yes` to answer every question with yes. Open a new terminal afterwards so the `sudosend` command is found.

> Just want to try it without installing? `./sudosend` inside the extracted folder works too.

### macOS

1. Download `sudosend-macos.zip`, unzip it and drag **SUDOSEND** into *Applications*.
2. The app is not notarized yet: the first time, **right-click → Open → Open**
   (or run `xattr -dr com.apple.quarantine /Applications/SUDOSEND.app`).
3. Allow *local network* access when macOS asks — otherwise devices can't find each other.

### iPhone / iPad

There is no App Store build yet (that needs a paid Apple developer account). You can sideload the
unsigned IPA with a free Apple ID using [AltStore](https://altstore.io) or
[Sideloadly](https://sideloadly.io): load `sudosend-ios-unsigned.ipa`, sign in, install.
Free-account installs must be refreshed every 7 days.

On iPhone, Apple blocks network discovery for unapproved apps, so **use QR pairing or *IP / link***:
scan the QR on the other device's Receive tab. Received files are in the **Files** app →
*On My iPhone → SUDOSEND*.

### One-line install (Linux)

Detects your CPU and distro, downloads the right file and installs it:

```bash
curl -fsSL https://raw.githubusercontent.com/sudosoc/SUDOSEND/main/get.sh | bash
```

> While the repository is **private**, this needs the GitHub CLI logged in (`sudo apt install gh && gh auth login`). Without it, download the file from the Releases page manually.

---

## First transfer

1. Open SUDOSEND on **both** devices, connected to the **same Wi-Fi or hotspot**.
2. On the sender, open the **Send** tab, then pick **Files**, **Folder** or **Text**.
3. Tap the receiver in **Nearby devices**.
4. Both screens show the same **6-digit code**. On the receiver, check it matches, then tap **Accept**.
   Tick **Trust this device** to skip the code next time.
5. Done. Every file is SHA-256 verified before it is saved.

**Faster: QR pairing.** On the receiver open **Receive**; on the phone tap **Scan QR** (Send tab).
Both devices now trust each other — no code, no prompt, now and next time.

If a device doesn't appear, use **IP / link** on the Send tab and type the IP shown on the receiver's
**Receive** tab (or paste its pairing link).

---

## Command line

Installed together with the app (`.deb`, `install.sh`, or the Windows installer with *Add to PATH*):

```bash
sudosend                                    # no arguments → opens the app
sudosend receive                            # wait for files, asks before accepting
sudosend receive --yes --trust --once       # unattended, exit after one transfer
sudosend receive --qr                       # print a pairing QR in the terminal
sudosend send report.pdf photos/ --to laptop      # device name (prefix) …
sudosend send --text "https://…" --to 192.168.1.20  # … or IP address
sudosend send file.iso --to 'sudosend://pair?…'     # … or a pairing link
sudosend devices                            # list devices on the network
sudosend id --name Seif-Pi                  # show/rename this device
tar c dir | sudosend send - --name dir.tar --to pi   # send from a pipe (stdin)
sudosend receive --receipts ~/receipts      # keep a signed receipt for every transfer
sudosend verify ~/receipts/receipt-*.json   # check receipts offline
sudosend web report.pdf                     # QR + link: any browser can download it
sudosend web --upload                       # let browsers send files to you
sudosend web secret.pdf --pin 4821 --max 1  # PIN-protected, self-destructs after 1 download
sudosend ring --to phone                    # find my phone (trusted devices)
sudosend send big.iso --to nas --limit 5M   # cap upload speed
sudosend --help
```

Standalone binaries (`sudosend-cli-*`) are on the Releases page for servers without a desktop.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `exec format error` on Linux | Wrong CPU build. `uname -m` says `aarch64` → use the **arm64** file. `x86_64` → **x64/amd64**. |
| `sudosend: command not found` after `./install.sh` | Open a new terminal, or run `export PATH="$HOME/.local/bin:$PATH"`. |
| Devices don't see each other | Same Wi-Fi? Guest, campus and café Wi-Fi often block device-to-device traffic (*client isolation*), so use a phone hotspot instead. Or use **By IP**. |
| Linux: other devices can't find mine | Firewall. `sudo ufw allow 47823/udp && sudo ufw allow 47824:47833/tcp && sudo ufw allow 47840:47849/tcp` (the last range is browser share) |
| Windows: other devices can't find the PC | Re-run the installer with the firewall option, or allow SUDOSEND on **Private** networks. Make sure the Wi-Fi network is set to *Private*, not *Public*. |
| *Pick files* does nothing on Linux | Install zenity: `sudo apt install zenity` |
| Window is blank or very slow on a Raspberry Pi | Use a 64-bit OS with the desktop (X11/Wayland) running. On very old boards, the CLI is lighter: `sudosend receive`. |
| *Fingerprint mismatch* error | Something on the network answered pretending to be that device. The transfer was blocked on purpose. |
| Android stops mid-transfer | Allow notifications for SUDOSEND (the transfer runs as a foreground service), and on Xiaomi/Huawei/Samsung set battery usage to *Unrestricted*. |
| Android: "App not installed" when updating | The new APK is signed with a different key than the installed one (only happens once, when moving to release-signed builds). Uninstall, then install. |
| Laggy UI on a Raspberry Pi or old phone | Settings → Visual effects → **Lite** (automatic on Raspberry Pi and low-RAM phones). |
| Browser link doesn't open on the other device | Both must be on the same Wi-Fi/hotspot; allow TCP 47840–47849 in your firewall. |
| Hotspot won't start (Android) | Turn off the normal hotspot/tethering, turn on Location (Android ≤ 12), allow *Nearby devices*. |
| Updated the app and devices ask for the code again | The device key couldn't be unlocked (e.g. OS key store reset) and was recreated — pair again. |

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
./setup.sh          # Windows: ./setup.ps1  — platform folders, packages, icons, tests
flutter run -d linux                # or: windows, or an Android device id
```

Release builds and packages:

```bash
flutter build apk --release
flutter build linux --release
./tool/build_cli.sh sudosend-cli
./tool/package_linux.sh build/linux/x64/release/bundle sudosend-cli x64   # → dist/*.tar.gz + *.deb
```

CI (`.github/workflows/ci.yml`) runs analysis, tests and a CLI-to-CLI end-to-end transfer, then builds
Android, Windows (installer + portable), Linux x64 and Linux ARM64 (tarball + .deb), and smoke-tests every
Linux installer. Bumping `version:` in `pubspec.yaml` publishes a new release automatically.

### Release signing (Android)

CI re-signs the APK with a permanent key when these repository secrets exist:
`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`
(*Settings → Secrets and variables → Actions*). Without them the APK is debug-signed and a
warning is shown in the run.

### Performance

Every CI run benchmarks the core on x64 and ARM64 (see the run's annotations): the optimised
ChaCha20-Poly1305 does ~100–110 MB/s per core on a 2-vCPU cloud runner (4–5× package:cryptography's
pure-Dart cipher), spread over a pool of worker isolates; SHA-256 of large files runs on its own
isolate. Real transfers are usually limited by Wi-Fi, not the CPU.

### Layout

```
lib/
  app/                  strings (EN/AR), scope
  state/                AppController, settings, history
  platform/             Android bridge, desktop helpers (open, notify, single instance)
  ui/                   glass widgets, tabs, settings, QR scanner
android/…/kotlin/       cached engine, foreground service, notifications, share, Keystore
packages/wraith_core/   pure-Dart protocol core, shared by the app and the CLI
  lib/wraith.dart         framing, handshake, pipelined secure channel
  lib/chacha_poly.dart    optimised RFC 8439 ChaCha20-Poly1305
  lib/aead.dart           AEAD engines (inline / isolate pool)
  lib/pairing.dart        QR pairing links
  lib/receipt.dart        signed delivery receipts
  lib/discovery.dart      UDP announce / probe / listen
  lib/transfer.dart       sender + receiver state machines (resume, folders, text)
  lib/identity.dart       Ed25519 identity, key vaults, trusted/blocked devices
  lib/vault_windows.dart  DPAPI seed vault
  bin/sudosend.dart       command-line client
packaging/              Linux install.sh, Windows Inno Setup script
tool/                   bootstrap, packaging, CI helpers
test/                   RFC 8439 vectors, loopback E2E: transfer, resume, tamper, folders,
                        text, spoofing, QR pairing, block list, flood limits, translations
```

---

## Comparison

| | SUDOSEND | LocalSend | KDE Connect | Quick Share |
|---|:-:|:-:|:-:|:-:|
| Android · Windows · Linux · macOS · iOS | ✅ | ✅ | ⚠️ iOS limited | ❌ no Linux / iOS |
| Works with no internet and no account | ✅ | ✅ | ✅ | ⚠️ account for some modes |
| Verify the other device (code or QR) | ✅ | — | ✅ pairing | ✅ |
| **Signed proof of delivery**, verifiable offline | ✅ | — | — | — |
| SHA-256 verification of every file | ✅ | — | — | — |
| Resume interrupted transfers | ✅ | — | — | — |
| Flood protection + block list | ✅ | — | — | — |
| CLI with pipes and terminal QR | ✅ | — | ⚠️ `kdeconnect-cli` | — |
| Universal clipboard | ✅ free | — | ✅ | — |
| Send to / receive from a plain browser | ✅ | ✅ send only | — | — |
| Built-in hotspot when there is no Wi-Fi | ✅ Android | — | — | ✅ |
| PIN-protected, self-destructing share links | ✅ free | — | — | — |
| Deliver to an offline device later (outbox) | ✅ | — | — | — |
| Find my device (ring) | ✅ free | — | ✅ | — |
| Upload speed limit | ✅ | — | — | — |
| Arabic UI with RTL | ✅ | ✅ | ✅ | ✅ |

*✅ yes · ⚠️ partly · ❌ no · — not offered or not documented. Based on each project's public
documentation as of late 2026 — corrections welcome via an issue.*

## Security

Wire protocol, threat model and design decisions: **[PROTOCOL.md](PROTOCOL.md)**.
X25519 ephemeral keys + Ed25519 identities, hash-committed handshake with a 6-digit SAS,
ChaCha20-Poly1305 with counter nonces, and SHA-256 on every file.

## Roadmap

- Send to several devices at once
- Wi-Fi Direct / hotspot mode when there is no router
- Signed & notarized builds (Windows code signing, Apple notarization, App Store / Play Store)

## License

[MIT](LICENSE) © SUDOSOC. Bundled font: IBM Plex Sans Arabic (SIL OFL 1.1).

<p align="center">Made by <b>SUDOSOC</b></p>
