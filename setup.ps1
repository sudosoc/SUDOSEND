# One-time setup on Windows: native folders, packages, icons, tests.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

flutter create --org com.sudosoc --project-name sudosend --platforms android,windows,linux . | Out-Null
flutter pub get
if (Test-Path windows/runner/main.cpp) {
  (Get-Content windows/runner/main.cpp) -replace 'L"sudosend"', 'L"SUDOSEND"' | Set-Content windows/runner/main.cpp
}
if (Test-Path linux/runner/my_application.cc) {
  (Get-Content linux/runner/my_application.cc) -replace '"sudosend"', '"SUDOSEND"' | Set-Content linux/runner/my_application.cc
}
dart run flutter_launcher_icons
flutter test

Write-Host ""
Write-Host "SUDOSEND is ready."
Write-Host "  App:  flutter run -d windows"
Write-Host "  CLI:  (cd packages/wraith_core && dart run bin/sudosend.dart) --help"
