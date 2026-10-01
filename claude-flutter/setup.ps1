# Сүнс илрүүлэгч — Flutter төсөл бэлдэх скрипт (Windows PowerShell)
# Ажиллуулах:  powershell -ExecutionPolicy Bypass -File .\setup.ps1
$ErrorActionPreference = "Stop"
$src    = $PSScriptRoot
$parent = Split-Path $src -Parent
$dst    = Join-Path $parent "ghost_detector"

Write-Host "== Flutter шалгаж байна ==" -ForegroundColor Cyan
flutter --version
if ($LASTEXITCODE -ne 0) { throw "Flutter олдсонгүй. https://docs.flutter.dev/get-started/install/windows" }

if (!(Test-Path $dst)) {
  Write-Host "== Шинэ Flutter төсөл үүсгэж байна: $dst ==" -ForegroundColor Cyan
  Push-Location $parent
  flutter create --org mn.acs --platforms android,ios ghost_detector
  Pop-Location
}

Write-Host "== Код, assets хуулж байна ==" -ForegroundColor Cyan
Copy-Item (Join-Path $src "lib")    $dst -Recurse -Force
Copy-Item (Join-Path $src "assets") $dst -Recurse -Force
Copy-Item (Join-Path $src "pubspec.yaml") $dst -Force
Copy-Item (Join-Path $src "README.md") $dst -Force
$defaultTest = Join-Path $dst "test\widget_test.dart"
if (Test-Path $defaultTest) { Remove-Item $defaultTest }   # MyApp-ийг хайдаг анхны тест

# ---- Бодит магнитометрийн native код (iOS CoreMotion / Android SensorManager) ----
$kt = Join-Path $dst "android\app\src\main\kotlin\mn\acs\ghost_detector\MainActivity.kt"
if (Test-Path (Split-Path $kt -Parent)) {
  Copy-Item (Join-Path $src "platform\android\MainActivity.kt") $kt -Force
  Write-Host "Android MainActivity.kt (магнитометр) хуулагдлаа" -ForegroundColor Green
} else { Write-Host "АНХААР: $kt олдсонгүй — package нэр өөр байж магадгүй" -ForegroundColor Yellow }
$swift = Join-Path $dst "ios\Runner\AppDelegate.swift"
if (Test-Path $swift) {
  Copy-Item (Join-Path $src "platform\ios\AppDelegate.swift") $swift -Force
  Write-Host "iOS AppDelegate.swift (CoreMotion магнитометр) хуулагдлаа" -ForegroundColor Green
}

function Write-NoBom($path, $text) {
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

# ---- Android зөвшөөрөл ----
$manifest = Join-Path $dst "android\app\src\main\AndroidManifest.xml"
$x = [System.IO.File]::ReadAllText($manifest)
if ($x -notmatch "android.permission.CAMERA") {
  $perms = @"

    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>
    <uses-feature android:name="android.hardware.sensor.compass" android:required="false"/>
"@
  $x = [regex]::Replace($x, "(<manifest[^>]*>)", "`$1$perms", 1)
}
if ($x -notmatch "requestLegacyExternalStorage") {
  $x = [regex]::Replace($x, "<application", "<application`r`n        android:requestLegacyExternalStorage=`"true`"", 1)
}
Write-NoBom $manifest $x
Write-Host "AndroidManifest.xml шинэчлэгдлээ" -ForegroundColor Green

# ---- iOS Info.plist ----
$plist = Join-Path $dst "ios\Runner\Info.plist"
if (Test-Path $plist) {
  $p = [System.IO.File]::ReadAllText($plist)
  $usageDescriptions = [ordered]@{
    NSCameraUsageDescription = "Орчны зураг, видео авахад камер ашиглана"
    NSMicrophoneUsageDescription = "Орчны дуу, ярианы бичлэгт микрофон ашиглана"
    NSPhotoLibraryAddUsageDescription = "Зураг, видеог Photos-д хадгална"
    NSMotionUsageDescription = "Хөдөлгөөн, чичиргээ, соронзон орны бодит хэмжилтэд мэдрэгч ашиглана"
  }
  foreach ($key in $usageDescriptions.Keys) {
    if ($p -notmatch "<key>$key</key>") {
      $entry = "`t<key>$key</key>`r`n`t<string>$($usageDescriptions[$key])</string>`r`n</dict>`r`n</plist>"
      $p = [regex]::Replace($p, "</dict>\s*</plist>\s*$", $entry)
    }
  }
  Write-NoBom $plist $p
  Write-Host "Info.plist шинэчлэгдлээ" -ForegroundColor Green
}

Write-Host "== Багцууд татаж байна ==" -ForegroundColor Cyan
Push-Location $dst
flutter pub get
Write-Host "== Кодыг шалгаж байна (flutter analyze) ==" -ForegroundColor Cyan
flutter analyze --no-fatal-infos | Tee-Object -FilePath (Join-Path $dst "analyze_log.txt")
Write-Host "== Холбогдсон төхөөрөмжүүд ==" -ForegroundColor Cyan
flutter devices
Pop-Location

Write-Host ""
Write-Host "Бэлэн! Утсаа USB-ээр холбоод:" -ForegroundColor Green
Write-Host "   cd `"$dst`""
Write-Host "   flutter run"
