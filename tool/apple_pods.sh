#!/usr/bin/env bash
# Prepares CocoaPods for an Apple platform build: lets Flutter generate and
# integrate the Podfile, pins the minimum OS, then installs pods.
#   tool/apple_pods.sh ios|macos
set -uo pipefail
cd "$(dirname "$0")/.."
platform="$1"
echo "== flutter build $platform --config-only"
if [ "$platform" = ios ]; then
  flutter build ios --config-only --release --no-codesign 2>&1 | tail -n 30
else
  flutter build macos --config-only --release 2>&1 | tail -n 30
fi
echo "== $platform dir:"; ls "$platform"
if [ ! -f "$platform/Podfile" ]; then
  echo "Podfile missing after config-only; copying Flutter's template"
  root="$(cd "$(dirname "$(readlink -f "$(command -v flutter)" 2>/dev/null || command -v flutter)")/.." && pwd)"
  cp "$root/packages/flutter_tools/templates/cocoapods/Podfile-$platform" "$platform/Podfile"
fi
if [ "$platform" = ios ]; then
  sed -i '' "s/^#* *platform :ios, '[0-9.]*'/platform :ios, '15.5'/" ios/Podfile
fi
echo "== Podfile platform:"; grep -n "platform :" "$platform/Podfile"
cd "$platform" && pod install --repo-update 2>&1 | tail -n 40
exit "${PIPESTATUS[0]}"
