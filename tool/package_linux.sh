#!/usr/bin/env bash
# Packages a Flutter Linux release bundle + the CLI into:
#   sudosend-linux-<x64|arm64>.tar.gz   (portable, with install.sh)
#   sudosend_<version>_<amd64|arm64>.deb (Debian / Ubuntu / Kali / Raspberry Pi OS)
#
# Usage: tool/package_linux.sh <bundle-dir> <cli-binary> <x64|arm64>
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$1"
cli="$2"
arch="$3"
case "$arch" in
  x64)   uname_arch=x86_64;  deb_arch=amd64 ;;
  arm64) uname_arch=aarch64; deb_arch=arm64 ;;
  *) echo "arch must be x64 or arm64"; exit 2 ;;
esac
version="$(grep -E '^version:' "$root/pubspec.yaml" | sed -E 's/version: *([0-9.]+).*/\1/')"
out="$root/dist"
work="$(mktemp -d)"
mkdir -p "$out"

# ── Portable tarball ──────────────────────────────────────────────────
app="$work/sudosend"
mkdir -p "$app"
cp -a "$bundle"/. "$app/"
cp "$cli" "$app/sudosend-cli"
cp "$root/packaging/linux/install.sh" "$app/install.sh"
cp "$root/packaging/linux/sudosend.png" "$app/sudosend.png"
echo "$uname_arch" > "$app/ARCH"
cat > "$app/README.txt" <<EOF
SUDOSEND $version for Linux ($uname_arch)

Install:    ./install.sh          (or: sudo ./install.sh for all users)
Run:        sudosend              (or find SUDOSEND in your app menu)
Uninstall:  sudosend --uninstall

Run without installing: ./sudosend
EOF
chmod 755 "$app/sudosend" "$app/sudosend-cli" "$app/install.sh"
tar -czf "$out/sudosend-linux-$arch.tar.gz" -C "$work" sudosend
echo "built dist/sudosend-linux-$arch.tar.gz"

# ── .deb package ──────────────────────────────────────────────────────
deb="$work/deb"
mkdir -p "$deb/DEBIAN" "$deb/opt/sudosend" "$deb/usr/bin" \
         "$deb/usr/share/applications" "$deb/usr/share/icons/hicolor/512x512/apps"
cp -a "$bundle"/. "$deb/opt/sudosend/"
cp "$cli" "$deb/opt/sudosend/sudosend-cli"
cp "$root/packaging/linux/sudosend.png" "$deb/usr/share/icons/hicolor/512x512/apps/sudosend.png"
chmod 755 "$deb/opt/sudosend/sudosend" "$deb/opt/sudosend/sudosend-cli"

cat > "$deb/usr/bin/sudosend" <<'EOF'
#!/bin/sh
# SUDOSEND launcher: no arguments → open the app; with arguments → CLI.
case "${1:-}" in
  "")          exec /opt/sudosend/sudosend ;;
  --uninstall) echo "Installed from a .deb — remove it with: sudo apt remove sudosend"; exit 0 ;;
  *)           exec /opt/sudosend/sudosend-cli "$@" ;;
esac
EOF
chmod 755 "$deb/usr/bin/sudosend"

cat > "$deb/usr/share/applications/sudosend.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=SUDOSEND
GenericName=Secure File Sharing
Comment=Send files, folders and text across your network, end-to-end encrypted
Exec=/opt/sudosend/sudosend
Icon=sudosend
Terminal=false
Categories=Network;FileTransfer;Utility;
Keywords=share;send;transfer;lan;airdrop;wifi;
StartupWMClass=sudosend
EOF

size_kb="$(du -sk "$deb/opt" | cut -f1)"
cat > "$deb/DEBIAN/control" <<EOF
Package: sudosend
Version: $version
Section: net
Priority: optional
Architecture: $deb_arch
Installed-Size: $size_kb
Depends: libgtk-3-0t64 | libgtk-3-0
Recommends: zenity
Maintainer: SUDOSOC <https://github.com/sudosoc>
Homepage: https://github.com/sudosoc/SUDOSEND
Description: Secure, local, instant file sharing (Wraith Protocol)
 Send files, whole folders and text between Android, Windows and Linux on
 the same network. End-to-end encrypted (X25519 + ChaCha20-Poly1305),
 verified with SHA-256, no cloud and no accounts. Includes the "sudosend"
 command-line client.
EOF

cat > "$deb/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t /usr/share/icons/hicolor || true
exit 0
EOF
cp "$deb/DEBIAN/postinst" "$deb/DEBIAN/postrm"
chmod 755 "$deb/DEBIAN/postinst" "$deb/DEBIAN/postrm"

dpkg-deb --build --root-owner-group "$deb" "$out/sudosend_${version}_${deb_arch}.deb" >/dev/null
echo "built dist/sudosend_${version}_${deb_arch}.deb"
rm -rf "$work"
