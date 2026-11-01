#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#  SUDOSEND one-line installer for Linux.
#
#    curl -fsSL https://raw.githubusercontent.com/sudosoc/SUDOSEND-APP/main/get.sh | bash
#
#  Detects your CPU (x86_64 / ARM64 e.g. Raspberry Pi) and distro, downloads the
#  latest release and installs it: the .deb on Debian/Ubuntu/Kali/Raspberry Pi OS,
#  otherwise the portable package + install.sh. Works with a private repo too if
#  the GitHub CLI (`gh`) is installed and logged in.
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail
REPO="sudosoc/SUDOSEND-APP"

if [ -t 1 ]; then G=$'\033[32m'; C=$'\033[36m'; R=$'\033[31m'; N=$'\033[0m'; else G= C= R= N=; fi
step() { printf '%s▸%s %s\n' "$C" "$N" "$*"; }
die()  { printf '%s✖ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }

case "$(uname -s)" in Linux) ;; *) die "This installer is for Linux. On Windows use the setup .exe, on Android the .apk." ;; esac
case "$(uname -m)" in
  x86_64|amd64)  arch=x64;   deb_arch=amd64 ;;
  aarch64|arm64) arch=arm64; deb_arch=arm64 ;;
  *) die "Unsupported CPU: $(uname -m). Builds exist for x86_64 and ARM64." ;;
esac

SUDO=""
[ "$(id -u)" != 0 ] && command -v sudo >/dev/null 2>&1 && SUDO=sudo
use_deb=0
command -v apt-get >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1 && use_deb=1

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ "$use_deb" = 1 ]; then pattern="sudosend_*_${deb_arch}.deb"; else pattern="sudosend-linux-${arch}.tar.gz"; fi
step "Downloading the latest SUDOSEND for $(uname -m) ($pattern)…"

downloaded=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh release download --repo "$REPO" --pattern "$pattern" --dir "$tmp" --clobber && downloaded=1
fi
if [ "$downloaded" = 0 ]; then
  command -v curl >/dev/null 2>&1 || die "curl is required"
  api="https://api.github.com/repos/$REPO/releases/latest"
  url="$(curl -fsSL "$api" 2>/dev/null | grep -oE '"browser_download_url": *"[^"]+"' | cut -d'"' -f4 \
        | grep -E "/$(printf '%s' "$pattern" | sed 's/\./\\./g; s/\*/[^\/]*/g')$" | head -n1 || true)"
  [ -n "$url" ] || die "Could not reach the release. If the repository is private, install the GitHub CLI and run 'gh auth login', or download the file manually from https://github.com/$REPO/releases"
  curl -fL --progress-bar -o "$tmp/$(basename "$url")" "$url"
fi

file="$(ls "$tmp" | head -n1)"
[ -n "$file" ] || die "Download failed"

if [ "$use_deb" = 1 ]; then
  step "Installing $file (apt resolves the dependencies)…"
  $SUDO apt-get install -y "$tmp/$file"
  printf '\n%s✔ SUDOSEND installed.%s Run: sudosend   (or open it from the app menu)\n' "$G" "$N"
else
  tar -xzf "$tmp/$file" -C "$tmp"
  "$tmp/sudosend/install.sh" --yes
fi
