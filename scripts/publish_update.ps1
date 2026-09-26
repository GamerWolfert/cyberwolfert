# Lokaal alles bouwen (zonder cloud): APK + Web + bundle.
# Gebruik: .\scripts\publish_update.ps1 -Version "1.8.0" -Notes "..." -ApiBaseUrl "http://192.168.1.42:43711/api"
param(
  [string]$Version = "",
  [string]$Notes = "Update",
  [string]$ApiBaseUrl = ""
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'app'
$env:Path = "C:\src\flutter\bin;$env:Path"

$pubspec = Join-Path $app 'pubspec.yaml'
$cur = (Select-String -Path $pubspec -Pattern '^version:\s*([0-9.]+)\+([0-9]+)').Matches[0].Groups
$oldVer, $oldBuild = $cur[1].Value, [int]$cur[2].Value
if ($Version -eq "") { $Version = $oldVer }
$newBuild = $oldBuild + 1
Write-Host "Versie: $oldVer+$oldBuild -> $Version+$newBuild"

(Get-Content $pubspec) -replace "^version:.*", "version: $Version+$newBuild" | Set-Content $pubspec

$svc = Join-Path $app 'lib\services\update_service.dart'
(Get-Content $svc) -replace 'static const int currentBuild = \d+;', "static const int currentBuild = $newBuild;" | Set-Content $svc

$verFile = Join-Path $root 'backend\version.json'
$verJson = Get-Content $verFile -Raw | ConvertFrom-Json
$verJson.version = $Version; $verJson.build = $newBuild
$verJson.notes = $Notes; $verJson.updatedAt = (Get-Date -Format 'yyyy-MM-dd')
$verJson | ConvertTo-Json | Set-Content $verFile

$defineArgs = @()
if ($ApiBaseUrl -ne "") { $defineArgs = @("--dart-define=API_BASE_URL=$ApiBaseUrl") }
Push-Location $app
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'pub get mislukt' }
  Write-Host 'APK bouwen...'
  flutter build apk --release @defineArgs
  if ($LASTEXITCODE -ne 0) { throw 'apk build mislukt' }
  Write-Host 'Web bouwen...'
  flutter build web --release @defineArgs
  if ($LASTEXITCODE -ne 0) { throw 'web build mislukt' }
  try {
    Write-Host 'Windows bouwen...'
    flutter build windows --release @defineArgs
    if ($LASTEXITCODE -ne 0) { throw 'windows build mislukt' }
    $winOk = $true
  } catch {
    $winOk = $false
    Write-Host 'Windows overgeslagen (vereist VS C++ workload + Developer Mode).'
  }
} finally {
  Pop-Location
}

$dl = Join-Path $root 'backend\downloads'
New-Item -ItemType Directory -Force -Path $dl | Out-Null
$apkSrc = Join-Path $app 'build\app\outputs\flutter-apk\app-release.apk'
Copy-Item $apkSrc (Join-Path $dl 'CyberWolfert.apk') -Force
Copy-Item $apkSrc (Join-Path $root 'CyberWolfert.apk') -Force
$webOut = Join-Path $app 'build\web'
$public = Join-Path $root 'backend\public'
Remove-Item $public -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $public | Out-Null
Copy-Item (Join-Path $webOut '*') $public -Recurse -Force
if ($winOk) {
  $exeDir = Join-Path $app 'build\windows\x64\runner\Release'
  if (Test-Path $exeDir) {
    Compress-Archive -Path (Join-Path $exeDir '*') -DestinationPath (Join-Path $dl 'CyberWolfert-Windows.zip') -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'windows-release') | Out-Null
    Copy-Item (Join-Path $exeDir '*') (Join-Path $root 'windows-release\') -Recurse -Force
  }
}

Copy-Item (Join-Path $root 'scripts\bundle-readme-template.txt') (Join-Path $dl 'INSTALLEREN-LEESMIJ.txt') -Force
$iosInfo = Join-Path $dl 'iOS-INFO.txt'
"IOS (iPhone/iPad):`nApple staat geen directe installatie toe.`nDownload de IPA via GitHub Actions (ios-build).`nZie INSTALLEREN-LEESMIJ.txt" |
  Set-Content $iosInfo
$bundleItems = @((Join-Path $dl 'CyberWolfert.apk'), (Join-Path $dl 'INSTALLEREN-LEESMIJ.txt'), $iosInfo)
if (Test-Path (Join-Path $dl 'CyberWolfert-Windows.zip')) { $bundleItems += (Join-Path $dl 'CyberWolfert-Windows.zip') }
Compress-Archive -Path $bundleItems -DestinationPath (Join-Path $dl 'CyberWolfert-apps.zip') -Force
Write-Host "KLAAR: $Version+$newBuild"
