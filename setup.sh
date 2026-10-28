#!/usr/bin/env bash
# One-time setup: native folders, packages, icons, tests.
set -euo pipefail
cd "$(dirname "$0")"
./tool/bootstrap.sh
flutter test

echo
echo "✔ SUDOSEND is ready."
echo "  App:  flutter run -d linux        (or: flutter devices)"
echo "  CLI:  dart run bin/sudosend.dart --help"
