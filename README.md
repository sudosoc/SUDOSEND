<p align="center"><img src="assets/icon.png" width="120" alt="SUDOSEND"></p>

<h1 align="center">SUDOSEND</h1>

<p align="center">
  <b>Secure. Local. Instant.</b><br>
  Encrypted file sharing between Android, Windows and Linux on the same network.<br>
  No cloud · no accounts · no internet.
</p>

<p align="center">
  <a href="https://github.com/sudosoc/SUDOSEND/actions/workflows/ci.yml"><img src="https://github.com/sudosoc/SUDOSEND/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/sudosoc/SUDOSEND/releases/latest"><img src="https://img.shields.io/github/v/release/sudosoc/SUDOSEND?label=release" alt="release"></a>
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
  - [One-line install (Linux)](#one-line-install-linux)
- [First transfer](#first-transfer)
- [Command line](#command-line)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Build from source](#build-from-source)
- [Security](#security)

---

## Features

- **Zero-config discovery** over multicast + broadcast, with *Send by IP* as a fallback
- **Files, whole folders, and text/clipboard**, folder structure preserved
- **Resume**: a dropped transfer continues where it stopped, re-verified end to end
- **End-to-end encryption**: X25519 + ChaCha20-Poly1305, fresh keys per transfer
- **MITM-proof first contact**: 6-digit verification code backed by a hash commitment
- **Trusted devices**: verify once, skip the code next time, revoke anytime
- **SHA-256 verification** of every file before it is kept
- **Hardened receiver**: path-traversal-safe names, size limits, explicit consent
- **Glassmorphism UI**: frosted glass, animated neon backdrop, live radar
- **CLI** for Linux and Windows, fully interoperable with the app

---

## Install

All files are on the **[Releases page](https://github.com/sudosoc/SUDOSEND/releases/latest)**.

### Which file do I download?

| Your device | Download | Install with |
|---|---|---|
| Android phone / tablet | `sudosend-android.apk` | tap it |
| Windows 10 / 11 | `sudosend-windows-x64-setup.exe` | double-click |
| Windows (no install) | `sudosend-windows-x64-portable.zip` | unzip, run `sudosend.exe` |
| Kali / Debian / Ubuntu / Mint on a **PC or laptop** | `sudosend_<version>_amd64.deb` | `sudo apt install ./sudosend_*_amd64.deb` |
| Kali / Raspberry Pi OS / Ubuntu on a **Raspberry Pi** or other ARM board | `sudosend_<version>_arm64.deb` | `sudo apt install ./sudosend_*_arm64.deb` |
| Fedora / Arch / openSUSE / other Linux | `sudosend-linux-x64.tar.gz` or `sudosend-linux-arm64.tar.gz` | `./install.sh` |

> **Linux: x64 or arm64?** Run `uname -m`.
> `x86_64` → **x64 / amd64**. `aarch64` → **arm64** (every Raspberry Pi 3/4/5 running a 64-bit OS).
> Running the wrong one gives `exec format error`.

### Android

1. Download `sudosend-android.apk` on the phone.
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

If a device doesn't appear, use **By IP** on the Send tab. The receiver's IP is shown on its **Receive** tab.

---

## Command line

Installed together with the app (`.deb`, `install.sh`, or the Windows installer with *Add to PATH*):

```bash
sudosend                                    # no arguments → opens the app
sudosend receive                            # wait for files, asks before accepting
sudosend receive --yes --trust --once       # unattended, exit after one transfer
sudosend send report.pdf photos/ --to laptop      # device name (prefix) …
sudosend send --text "https://…" --to 192.168.1.20  # … or IP address
sudosend devices                            # list devices on the network
sudosend id --name Seif-Pi                  # show/rename this device
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
| Linux: other devices can't find mine | Firewall. `sudo ufw allow 47823/udp && sudo ufw allow 47824:47833/tcp` |
| Windows: other devices can't find the PC | Re-run the installer with the firewall option, or allow SUDOSEND on **Private** networks. Make sure the Wi-Fi network is set to *Private*, not *Public*. |
| *Pick files* does nothing on Linux | Install zenity: `sudo apt install zenity` |
| Window is blank or very slow on a Raspberry Pi | Use a 64-bit OS with the desktop (X11/Wayland) running. On very old boards, the CLI is lighter: `sudosend receive`. |
| *Fingerprint mismatch* error | Something on the network answered pretending to be that device. The transfer was blocked on purpose. |

---

## Uninstall

| Installed with | Remove with |
|---|---|
| `.deb` | `sudo apt remove sudosend` |
| `install.sh` | `sudosend --uninstall` |
| Windows installer | *Settings → Apps → SUDOSEND → Uninstall* |
| Android | long-press the icon → *Uninstall* |

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

### Layout

```
lib/                    Flutter app (glass UI, state)
packages/wraith_core/   pure-Dart protocol core, shared by the app and the CLI
  lib/wraith.dart         framing, handshake, secure channel
  lib/discovery.dart      UDP announce / probe / listen
  lib/transfer.dart       sender + receiver state machines (resume, folders, text)
  lib/identity.dart       Ed25519 identity + trust store
  bin/sudosend.dart       command-line client
packaging/              Linux install.sh, Windows Inno Setup script
tool/                   bootstrap, packaging, CI helpers
test/                   loopback E2E: transfer, resume, tamper, folders, text, spoofing
```

---

## Security

Wire protocol, threat model and design decisions: **[PROTOCOL.md](PROTOCOL.md)**.
X25519 ephemeral keys + Ed25519 identities, hash-committed handshake with a 6-digit SAS,
ChaCha20-Poly1305 with counter nonces, and SHA-256 on every file.

## Roadmap

- **v0.3**: QR pairing, Android share-sheet target, persistent transfer history
- **v0.4**: hotspot mode, multiple receivers, native (Rust) crypto core

<p align="center">Made by <b>SUDOSOC</b></p>
