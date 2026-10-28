# Generates the native platform folders around the SUDOSEND sources (Windows).
# Existing files (lib\, test\, AndroidManifest.xml, MainActivity.kt) are kept.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

flutter create --org com.sudosoc --project-name sudosend --platforms android,windows,linux .
flutter pub get
flutter test

Write-Host ""
Write-Host "SUDOSEND is ready."
Write-Host "  Windows: flutter run -d windows"
Write-Host "  Android: flutter run -d <device-id>   (flutter devices)"
