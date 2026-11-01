#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  SUDOSEND installer for Linux (any distro, x86_64 or ARM64)
#
#  Run it from the extracted folder:
#     ./install.sh               install for your user   (~/.local, no root)
#     sudo ./install.sh          install for all users   (/opt/sudosend)
#     ./install.sh --yes         don't ask anything
#     ./install.sh --uninstall   remove SUDOSEND
#
#  What it does: checks the CPU architecture, installs the GTK runtime and a
#  file-picker helper if missing, copies the app, creates the `sudosend`
#  command and a menu entry, and (if a firewall is active) opens the ports.
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
YES=0
UNINSTALL=0

usage() { sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; }

for arg in "$@"; do
  case "$arg" in
    -y|--yes) YES=1 ;;
    -u|--uninstall) UNINSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $arg"; usage; exit 2 ;;
  esac
done

if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; N=$'\033[0m'; else B= G= Y= R= C= N=; fi
step() { printf '%s▸%s %s\n' "$C" "$N" "$*"; }
ok()   { printf '%s✔%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '%s✖ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
ask() {
  [ "$YES" = 1 ] && return 0
  local reply
  read -r -p "  $1 [Y/n] " reply </dev/tty 2>/dev/null || return 0
  case "$reply" in n|N|no|NO) return 1 ;; *) return 0 ;; esac
}

# ── Where to install ─────────────────────────────────────────────────────
if [ "$(id -u)" = 0 ]; then
  SYSTEM=1
  PREFIX=/opt/sudosend
  BIN=/usr/local/bin
  APPS=/usr/share/applications
  ICONS=/usr/share/icons/hicolor/512x512/apps
  SUDO=""
else
  SYSTEM=0
  PREFIX="$HOME/.local/share/sudosend"
  BIN="$HOME/.local/bin"
  APPS="$HOME/.local/share/applications"
  ICONS="$HOME/.local/share/icons/hicolor/512x512/apps"
  SUDO=""
  command -v sudo >/dev/null 2>&1 && SUDO=sudo
fi

refresh_menus() {
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$APPS" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$(dirname "$(dirname "$ICONS")")" 2>/dev/null || true
}

# ── Uninstall ────────────────────────────────────────────────────────────
if [ "$UNINSTALL" = 1 ]; then
  step "Removing SUDOSEND from $PREFIX"
  rm -rf "$PREFIX" "$BIN/sudosend" "$APPS/sudosend.desktop" "$ICONS/sudosend.png"
  refresh_menus
  ok "SUDOSEND removed. Your received files and identity were kept:"
  echo "    ~/Downloads/SUDOSEND, ~/.local/share/com.sudosoc.sudosend, ~/.config/sudosend"
  exit 0
fi

printf '\n%s  SUDOSEND installer%s  (%s)\n\n' "$B" "$N" "$([ $SYSTEM = 1 ] && echo "system-wide → $PREFIX" || echo "for $USER → $PREFIX")"

# ── 1. Architecture ──────────────────────────────────────────────────────
want="$(cat "$SRC/ARCH" 2>/dev/null || echo unknown)"
host="$(uname -m)"
[ "$host" = arm64 ] && host=aarch64
if [ "$want" != "$host" ]; then
  case "$host" in
    aarch64) right=arm64 ;;
    x86_64)  right=x64 ;;
    *)       right="$host (not built yet)" ;;
  esac
  die "This package is for $want, but this machine is $host.
   Download sudosend-linux-$right.tar.gz (or the matching .deb) from the Releases page instead."
fi
ok "Architecture: $host"

[ -x "$SRC/sudosend" ] || chmod +x "$SRC/sudosend" 2>/dev/null || true
[ -f "$SRC/sudosend" ] || die "Run this script from the extracted sudosend folder."

# ── 2. Runtime dependencies ──────────────────────────────────────────────
have_lib() {
  local cache
  cache="$( /sbin/ldconfig -p 2>/dev/null || ldconfig -p 2>/dev/null || true )"
  case "$cache" in *"$1"*) return 0 ;; esac
  for d in /usr/lib /usr/lib64 /lib /lib64 /usr/lib/x86_64-linux-gnu /usr/lib/aarch64-linux-gnu; do
    ls "$d"/"$1"* >/dev/null 2>&1 && return 0
  done
  return 1
}

pkg_install() {   # pkg_install <apt names> <dnf names> <pacman names> <zypper names>
  if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update -qq >/dev/null 2>&1 || true
    for p in $1; do $SUDO apt-get install -y -qq "$p" >/dev/null 2>&1 && return 0; done
  elif command -v dnf >/dev/null 2>&1; then $SUDO dnf install -y -q $2 && return 0
  elif command -v pacman >/dev/null 2>&1; then $SUDO pacman -S --needed --noconfirm $3 && return 0
  elif command -v zypper >/dev/null 2>&1; then $SUDO zypper -n -q in $4 && return 0
  fi
  return 1
}

if have_lib libgtk-3.so.0; then
  ok "GTK 3 runtime found"
else
  step "Installing the GTK 3 runtime (needed to draw the window)…"
  pkg_install "libgtk-3-0t64 libgtk-3-0" "gtk3" "gtk3" "gtk3" \
    && ok "GTK 3 installed" \
    || die "Could not install GTK 3 automatically. Install your distro's 'gtk3' / 'libgtk-3-0' package and re-run."
fi

if command -v zenity >/dev/null 2>&1 || command -v kdialog >/dev/null 2>&1; then
  ok "File picker helper found"
else
  step "Installing zenity (used by the file picker)…"
  pkg_install "zenity" "zenity" "zenity" "zenity" && ok "zenity installed" \
    || warn "zenity is missing — the 'Pick files' dialog may not open. Install 'zenity' manually."
fi

# ── 3. Copy the app ──────────────────────────────────────────────────────
step "Copying files…"
rm -rf "$PREFIX"
mkdir -p "$PREFIX"
cp -a "$SRC/sudosend" "$SRC/lib" "$SRC/data" "$PREFIX/"
[ -f "$SRC/sudosend-cli" ] && cp -a "$SRC/sudosend-cli" "$PREFIX/" && chmod 755 "$PREFIX/sudosend-cli"
cp -a "$SRC/install.sh" "$PREFIX/install.sh"
cp -a "$SRC/sudosend.png" "$PREFIX/sudosend.png" 2>/dev/null || true
chmod 755 "$PREFIX/sudosend" "$PREFIX/install.sh"
ok "Installed to $PREFIX"

# ── 4. The `sudosend` command ────────────────────────────────────────────
mkdir -p "$BIN"
cat > "$BIN/sudosend" <<EOF
#!/bin/sh
# SUDOSEND launcher: no arguments → open the app; with arguments → CLI.
APP_DIR="$PREFIX"
case "\${1:-}" in
  "")          exec "\$APP_DIR/sudosend" ;;
  --uninstall) exec "\$APP_DIR/install.sh" --uninstall ;;
  *)           exec "\$APP_DIR/sudosend-cli" "\$@" ;;
esac
EOF
chmod 755 "$BIN/sudosend"
ok "Command: $BIN/sudosend"

# ── 5. Menu entry ────────────────────────────────────────────────────────
mkdir -p "$APPS" "$ICONS"
cp -a "$SRC/sudosend.png" "$ICONS/sudosend.png" 2>/dev/null || true
cat > "$APPS/sudosend.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=SUDOSEND
GenericName=Secure File Sharing
Comment=Send files, folders and text across your network, end-to-end encrypted
Exec=$PREFIX/sudosend %F
Icon=$ICONS/sudosend.png
Terminal=false
Categories=Network;FileTransfer;Utility;
Keywords=share;send;transfer;lan;airdrop;wifi;
StartupWMClass=sudosend
EOF
refresh_menus
ok "Added SUDOSEND to the applications menu"

# ── 6. PATH (per-user installs) ──────────────────────────────────────────
if [ "$SYSTEM" = 0 ] && ! printf ':%s:' "$PATH" | grep -q ":$BIN:"; then
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$rc" ] && ! grep -q '.local/bin' "$rc"; then
      printf '\n# Added by the SUDOSEND installer\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
      ok "Added ~/.local/bin to PATH in $(basename "$rc")"
    fi
  done
  NEW_SHELL=1
fi

# ── 7. Firewall ──────────────────────────────────────────────────────────
if command -v ufw >/dev/null 2>&1 && $SUDO ufw status 2>/dev/null | grep -q "Status: active"; then
  if ask "ufw is active. Open SUDOSEND ports (47823/udp, 47824-47833/tcp, 47840-47849/tcp for browser share)?"; then
    $SUDO ufw allow 47823/udp comment SUDOSEND >/dev/null
    $SUDO ufw allow 47824:47833/tcp comment SUDOSEND >/dev/null
    $SUDO ufw allow 47840:47849/tcp comment "SUDOSEND browser share" >/dev/null
    ok "Firewall ports opened (ufw)"
  fi
elif command -v firewall-cmd >/dev/null 2>&1 && $SUDO firewall-cmd --state >/dev/null 2>&1; then
  if ask "firewalld is active. Open SUDOSEND ports (47823/udp, 47824-47833/tcp, 47840-47849/tcp for browser share)?"; then
    $SUDO firewall-cmd -q --permanent --add-port=47823/udp --add-port=47824-47833/tcp --add-port=47840-47849/tcp
    $SUDO firewall-cmd -q --reload
    ok "Firewall ports opened (firewalld)"
  fi
else
  ok "No active firewall detected"
fi

# ── Done ─────────────────────────────────────────────────────────────────
printf '\n%s  SUDOSEND is installed.%s\n\n' "$G$B" "$N"
echo "  Open the app      →  SUDOSEND in your applications menu, or run: sudosend"
echo "  Receive (CLI)     →  sudosend receive"
echo "  Send (CLI)        →  sudosend send <file|folder> --to <device|ip>"
echo "  Uninstall         →  sudosend --uninstall"
[ "${NEW_SHELL:-0}" = 1 ] && printf '\n  %sOpen a new terminal%s (or run: export PATH="$HOME/.local/bin:$PATH") to use the sudosend command.\n' "$Y" "$N"
echo
