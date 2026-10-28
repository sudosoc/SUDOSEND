#!/usr/bin/env bash
# Makes sure the Android build has a usable NDK. Tries the version Flutter
# expects; if the runner cannot download it, pins the newest NDK that is
# already installed on the machine.
set -uo pipefail
cd "$(dirname "$0")/.."
flutter_root="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"
want=$(grep -rhoE 'ndkVersion[^"]*"[0-9]+\.[0-9]+\.[0-9]+"' "$flutter_root/packages/flutter_tools/gradle" 2>/dev/null \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
mgr="$sdk/cmdline-tools/latest/bin/sdkmanager"
echo "Flutter wants NDK ${want:-unknown}; installed: $(ls "$sdk/ndk" 2>/dev/null | tr '\n' ' ')"

if [ -n "$want" ] && [ -f "$sdk/ndk/$want/source.properties" ]; then echo "already installed"; exit 0; fi
if [ -n "$want" ]; then
  for attempt in 1 2; do
    rm -rf "$sdk/ndk/$want"
    if yes | "$mgr" --install "ndk;$want" > /tmp/ndk.log 2>&1 && [ -f "$sdk/ndk/$want/source.properties" ]; then
      echo "NDK $want installed"; exit 0
    fi
    tail -n 5 /tmp/ndk.log; sleep 5
  done
  rm -rf "$sdk/ndk/$want"
fi

fallback=$(ls "$sdk/ndk" 2>/dev/null | grep -E '^[0-9]+\.' | sort -V | tail -n1)
if [ -z "$fallback" ]; then echo "::error::no NDK available"; exit 1; fi
echo "Pinning preinstalled NDK $fallback"
gradle=android/app/build.gradle.kts
[ -f "$gradle" ] || gradle=android/app/build.gradle
sed -i -E "s/ndkVersion *= *flutter\.ndkVersion/ndkVersion = \"$fallback\"/; s/ndkVersion +flutter\.ndkVersion/ndkVersion \"$fallback\"/" "$gradle"
grep -n ndkVersion "$gradle"
