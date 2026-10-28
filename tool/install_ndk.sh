#!/usr/bin/env bash
# Pre-installs the NDK version Flutter expects, with retries. GitHub runners
# occasionally get a corrupted NDK zip when Gradle downloads it on demand.
set -uo pipefail
flutter_root="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
ver=$(grep -rhoE 'ndkVersion[^"]*"[0-9]+\.[0-9]+\.[0-9]+"' "$flutter_root/packages/flutter_tools/gradle" 2>/dev/null \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
if [ -z "$ver" ]; then echo "could not detect NDK version; letting Gradle handle it"; exit 0; fi
sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
mgr="$sdk/cmdline-tools/latest/bin/sdkmanager"
echo "Installing NDK $ver"
for attempt in 1 2 3 4; do
  rm -rf "$sdk/ndk/$ver"
  if yes | "$mgr" --install "ndk;$ver" >/dev/null && [ -f "$sdk/ndk/$ver/source.properties" ]; then
    echo "NDK $ver installed (attempt $attempt)"; exit 0
  fi
  echo "attempt $attempt failed, retrying…"; sleep 10
done
echo "::error::NDK $ver install failed after retries"; exit 1
