#!/usr/bin/env bash
# Publishes dist/* as a GitHub Release. Every asset gets a display label with
# its platform in parentheses, e.g. "SUDOSEND (Android) — arm64-v8a", while
# the file names stay shell-friendly for scripts like get.sh.
#   tool/publish_release.sh <tag> <dist-dir>
set -euo pipefail
tag="$1"
dist="$2"
repo="${GITHUB_REPOSITORY:-sudosoc/SUDOSEND}"
ver="${tag#v}"

label() {
  case "$1" in
    sudosend-android-arm64-v8a.apk)     echo "SUDOSEND (Android) — arm64-v8a · most phones" ;;
    sudosend-android-armeabi-v7a.apk)   echo "SUDOSEND (Android) — armeabi-v7a · older 32-bit phones" ;;
    sudosend-android-x86_64.apk)        echo "SUDOSEND (Android) — x86_64 · emulators & Chromebooks" ;;
    sudosend-android-universal.apk)     echo "SUDOSEND (Android) — universal · any CPU, larger" ;;
    sudosend-ios-unsigned.ipa)          echo "SUDOSEND (iOS) — iPhone & iPad · unsigned, sideload" ;;
    sudosend-windows-x64-setup.exe)     echo "SUDOSEND (Windows) — installer · x64" ;;
    sudosend-windows-x64-portable.zip)  echo "SUDOSEND (Windows) — portable · x64" ;;
    sudosend-macos.zip)                 echo "SUDOSEND (macOS) — Apple Silicon & Intel" ;;
    sudosend_*_amd64.deb)               echo "SUDOSEND (Linux) — .deb · PC x86_64 · Kali/Debian/Ubuntu" ;;
    sudosend_*_arm64.deb)               echo "SUDOSEND (Linux) — .deb · ARM64 · Raspberry Pi" ;;
    sudosend-linux-x64.tar.gz)          echo "SUDOSEND (Linux) — portable · x86_64 · any distro" ;;
    sudosend-linux-arm64.tar.gz)        echo "SUDOSEND (Linux) — portable · ARM64 · any distro" ;;
    sudosend-cli-linux-x64)             echo "SUDOSEND CLI (Linux) — x86_64" ;;
    sudosend-cli-linux-arm64)           echo "SUDOSEND CLI (Linux) — ARM64" ;;
    sudosend-cli-windows-x64.exe)       echo "SUDOSEND CLI (Windows) — x64" ;;
    sudosend-cli-macos-arm64)           echo "SUDOSEND CLI (macOS) — Apple Silicon" ;;
    *)                                  echo "$1" ;;
  esac
}

notes="$(mktemp)"
cat > "$notes" <<NOTES
## Downloads

| | System | File |
|---|---|---|
| 🤖 | **Android** — most phones | \`sudosend-android-arm64-v8a.apk\` |
| 🤖 | **Android** — older 32-bit phones | \`sudosend-android-armeabi-v7a.apk\` |
| 🤖 | **Android** — not sure? | \`sudosend-android-universal.apk\` |
| 🍎 | **iOS** — iPhone / iPad (sideload) | \`sudosend-ios-unsigned.ipa\` |
| 🪟 | **Windows** 10/11 | \`sudosend-windows-x64-setup.exe\` · or portable \`.zip\` |
| 🍏 | **macOS** 11+ | \`sudosend-macos.zip\` |
| 🐧 | **Linux** PC — Kali / Debian / Ubuntu | \`sudosend_${ver}_amd64.deb\` |
| 🐧 | **Linux** Raspberry Pi / ARM64 | \`sudosend_${ver}_arm64.deb\` |
| 🐧 | **Linux** any distro | \`sudosend-linux-x64.tar.gz\` / \`-arm64.tar.gz\` → \`./install.sh\` |
| ⌨️ | **CLI** only | \`sudosend-cli-*\` |

**Which Android file?** Settings → About phone → look for *arm64* / *64-bit* → \`arm64-v8a\`. Unsure → \`universal\`.
**Which Linux file?** Run \`uname -m\`: \`x86_64\` → amd64/x64, \`aarch64\` → arm64.

One-line Linux install: \`curl -fsSL https://raw.githubusercontent.com/${repo}/main/get.sh | bash\`

Full guide: [README](https://github.com/${repo}#install)
NOTES

gh release create "$tag" --repo "$repo" --title "SUDOSEND $tag" --notes-file "$notes" \
  --target "${GITHUB_SHA:-main}" --generate-notes
for f in "$dist"/*; do
  name="$(basename "$f")"
  gh release upload "$tag" --repo "$repo" "$f#$(label "$name")"
  echo "uploaded $name → $(label "$name")"
done
