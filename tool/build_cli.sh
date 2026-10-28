#!/usr/bin/env bash
# Builds the standalone sudosend CLI from the pure-Dart core package.
# Usage: tool/build_cli.sh <output-path>
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-sudosend}"
case "$out" in /*|[A-Za-z]:*) ;; *) out="$root/$out" ;; esac
cd "$root/packages/wraith_core"
dart pub get
dart compile exe bin/sudosend.dart -o "$out"
