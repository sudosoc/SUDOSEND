#!/usr/bin/env bash
# Re-signs a release APK with the project's permanent key so every build can
# be installed as an update over the previous one.
#
# Needs these GitHub Actions secrets (see README → "Release signing"):
#   ANDROID_KEYSTORE_BASE64  base64 of the .jks file
#   ANDROID_STORE_PASSWORD   keystore password
#   ANDROID_KEY_PASSWORD     key password
#   ANDROID_KEY_ALIAS        key alias
#
# Without them the APK keeps Flutter's debug signature and a warning is shown.
set -euo pipefail
apk="$1"
if [ -z "${ANDROID_KEYSTORE_BASE64:-}" ]; then
  echo "::warning title=APK signing::ANDROID_KEYSTORE_BASE64 secret not set — the APK is debug-signed and cannot be installed as an update over other builds."
  exit 0
fi
ks="$(mktemp --suffix=.jks)"
trap 'rm -f "$ks"' EXIT
printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$ks"
sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
bt="$(ls -d "$sdk"/build-tools/* | sort -V | tail -n1)"
"$bt/apksigner" sign \
  --ks "$ks" --ks-pass env:ANDROID_STORE_PASSWORD \
  --ks-key-alias "$ANDROID_KEY_ALIAS" --key-pass env:ANDROID_KEY_PASSWORD \
  "$apk"
cert="$("$bt/apksigner" verify --print-certs "$apk" | grep -m1 'SHA-256 digest' | awk '{print $NF}')"
echo "::notice title=APK signed::release key SHA-256 $cert"
