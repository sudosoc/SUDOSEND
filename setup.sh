#!/usr/bin/env bash
# Generates the native platform folders around the SUDOSEND sources.
# Existing files (lib/, test/, AndroidManifest.xml, MainActivity.kt) are kept.
set -euo pipefail
cd "$(dirname "$0")"

flutter create --org com.sudosoc --project-name sudosend --platforms android,windows,linux .
flutter pub get
flutter test

echo
echo "✔ SUDOSEND is ready."
echo "  Linux:   flutter run -d linux"
echo "  Android: flutter run -d <device-id>   (flutter devices)"
