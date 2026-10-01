# Сүнс илрүүлэгч — Flutter төсөл бэлдэх скрипт (Windows PowerShell)
# Ажиллуулах:  powershell -ExecutionPolicy Bypass -File .\setup.ps1
$ErrorActionPreference = "Stop"
$src = $PSScriptRoot
$dst = Join-Path (Split-Path $src -Parent) "ghost_detector"
python (Join-Path $src "prepare_native.py") $dst
if ($LASTEXITCODE -ne 0) { throw "Native project preparation failed" }
Push-Location $dst
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
  flutter analyze --no-fatal-infos
  if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed" }
  flutter test
  if ($LASTEXITCODE -ne 0) { throw "flutter test failed" }
  flutter devices
} finally { Pop-Location }

Write-Host ""
Write-Host "Бэлэн! Утсаа USB-ээр холбоод:" -ForegroundColor Green
Write-Host "   cd `"$dst`""
Write-Host "   flutter run"
