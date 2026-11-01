#!/usr/bin/env bash
# Generates native platform folders around the SUDOSEND sources and brands them.
# Used by setup.sh and CI. Existing files (lib/, AndroidManifest.xml,
# Kotlin sources, tests) are never overwritten by `flutter create`.
#
#   PLATFORMS=android,windows,linux tool/bootstrap.sh     (default)
#   PLATFORMS=macos,ios tool/bootstrap.sh                 (on a Mac)
set -euo pipefail
cd "$(dirname "$0")/.."
PLATFORMS="${PLATFORMS:-android,windows,linux}"
has() { case ",$PLATFORMS," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
sedi() { sed -i.bak "$1" "$2" && rm -f "$2.bak"; }

flutter create --org com.sudosoc --project-name sudosend --platforms "$PLATFORMS" . >/dev/null
flutter pub get
FLUTTER_ROOT="$(dirname "$(dirname "$(command -v flutter)")")"
[ -d "$FLUTTER_ROOT/packages/flutter_tools" ] || FLUTTER_ROOT="$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")"

# ── Window titles: "sudosend" → "SUDOSEND" ───────────────────────────
[ -f linux/runner/my_application.cc ] && sedi 's/"sudosend"/"SUDOSEND"/g' linux/runner/my_application.cc
[ -f windows/runner/main.cpp ] && sedi 's/L"sudosend"/L"SUDOSEND"/g' windows/runner/main.cpp

# ── Android: androidx.core for notifications, FileProvider, services ──
if has android; then
  gradle=android/app/build.gradle.kts
  if [ -f "$gradle" ] && ! grep -q 'androidx.core:core-ktx' "$gradle"; then
    printf '\ndependencies {\n    implementation("androidx.core:core-ktx:1.13.1")\n}\n' >> "$gradle"
  fi
  gradle=android/app/build.gradle
  if [ -f "$gradle" ] && ! grep -q 'androidx.core:core-ktx' "$gradle"; then
    printf "\ndependencies {\n    implementation 'androidx.core:core-ktx:1.13.1'\n}\n" >> "$gradle"
  fi
  grep -q CHANGE_WIFI_MULTICAST_STATE android/app/src/main/AndroidManifest.xml
  grep -q acquireMulticastLock android/app/src/main/kotlin/com/sudosoc/sudosend/Bridge.kt
fi

# ── Apple platforms: permissions, sandbox entitlements, min OS ───────
plist_set() { # file key type value
  /usr/libexec/PlistBuddy -c "Add :$2 $3 $4" "$1" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :$2 $4" "$1"
}
if has macos; then
  for ent in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
    plist_set "$ent" com.apple.security.network.server bool true
    plist_set "$ent" com.apple.security.network.client bool true
    plist_set "$ent" com.apple.security.files.user-selected.read-write bool true
    plist_set "$ent" com.apple.security.files.downloads.read-write bool true
    plist_set "$ent" com.apple.security.device.camera bool true
  done
  plist_set macos/Runner/Info.plist NSLocalNetworkUsageDescription string "SUDOSEND finds and talks to your devices on the local network."
  plist_set macos/Runner/Info.plist NSCameraUsageDescription string "Scan a SUDOSEND pairing QR code."
  if [ ! -f macos/Podfile ]; then
    cp "$FLUTTER_ROOT/packages/flutter_tools/templates/cocoapods/Podfile-macos" macos/Podfile
  fi
  sedi "s/^#* *platform :osx, '[0-9.]*'/platform :osx, '10.15'/" macos/Podfile
  sedi 's/MACOSX_DEPLOYMENT_TARGET = 10\.[0-9]*;/MACOSX_DEPLOYMENT_TARGET = 10.15;/g' macos/Runner.xcodeproj/project.pbxproj
  sedi 's/^PRODUCT_NAME = .*/PRODUCT_NAME = SUDOSEND/' macos/Runner/Configs/AppInfo.xcconfig
fi
if has ios; then
  plist_set ios/Runner/Info.plist NSLocalNetworkUsageDescription string "SUDOSEND finds and talks to your devices on the local network."
  plist_set ios/Runner/Info.plist NSCameraUsageDescription string "Scan a SUDOSEND pairing QR code."
  plist_set ios/Runner/Info.plist UIFileSharingEnabled bool true
  plist_set ios/Runner/Info.plist LSSupportsOpeningDocumentsInPlace bool true
  plist_set ios/Runner/Info.plist CFBundleDisplayName string SUDOSEND
  if [ ! -f ios/Podfile ]; then
    cp "$FLUTTER_ROOT/packages/flutter_tools/templates/cocoapods/Podfile-ios" ios/Podfile
  fi
  sedi "s/^#* *platform :ios, '[0-9.]*'/platform :ios, '15.5'/" ios/Podfile
  sedi 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]*;/IPHONEOS_DEPLOYMENT_TARGET = 15.5;/g' ios/Runner.xcodeproj/project.pbxproj
fi

# ── Launcher icons ───────────────────────────────────────────────────
dart run flutter_launcher_icons

echo "bootstrap ($PLATFORMS): ok"
