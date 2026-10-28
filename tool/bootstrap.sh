#!/usr/bin/env bash
# Generates native platform folders around the SUDOSEND sources and brands them.
# Used by setup.sh and CI. Existing files (lib/, AndroidManifest.xml,
# MainActivity.kt, tests) are never overwritten by `flutter create`.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --org com.sudosoc --project-name sudosend --platforms android,windows,linux . >/dev/null
flutter pub get

# Window titles: "sudosend" → "SUDOSEND"
if [ -f linux/runner/my_application.cc ]; then
  sed -i.bak 's/"sudosend"/"SUDOSEND"/g' linux/runner/my_application.cc && rm -f linux/runner/my_application.cc.bak
fi
if [ -f windows/runner/main.cpp ]; then
  sed -i.bak 's/L"sudosend"/L"SUDOSEND"/g' windows/runner/main.cpp && rm -f windows/runner/main.cpp.bak
fi

# Launcher icons (Android adaptive + Windows .ico)
dart run flutter_launcher_icons

grep -q CHANGE_WIFI_MULTICAST_STATE android/app/src/main/AndroidManifest.xml
grep -q acquireMulticastLock android/app/src/main/kotlin/com/sudosoc/sudosend/MainActivity.kt
echo "bootstrap: ok"
