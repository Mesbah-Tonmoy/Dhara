# Builds the release and gets it ready to be installed: a folder that runs on
# a PC without Flutter or Visual Studio, with every bundled library checked
# against the list in tool/bundled-libraries.sha256.
#
#   pwsh tool/package.ps1
#   pwsh tool/package.ps1 -Flutter D:\dev\flutter\bin\flutter.bat
#
# Run it from anywhere; it works on the repository it lies in. Nothing is
# installed, nothing outside the repository's build/ and dist/ is written,
# and no admin rights are needed.
#
# -TestDataDir <folder> makes a copy for trying the installer without
# touching the real library: that build keeps its data in <folder>, is called
# "Dhara Test" and installs beside the real app, never over it.
[CmdletBinding()]
param(
  [string]$Flutter,
  [string]$TestDataDir
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Fail([string]$message) { Write-Host "package: $message" -ForegroundColor Red; exit 1 }
function Step([string]$message) { Write-Host "== $message" -ForegroundColor Cyan }
function SizeMb([string]$path) {
  $bytes = (Get-ChildItem $path -Recurse -File | Measure-Object Length -Sum).Sum
  [math]::Round($bytes / 1MB, 1)
}

# --- What is being packaged ---------------------------------------------------
$versionLine = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\d+\.\d+\.\d+)' | Select-Object -First 1
if (-not $versionLine) { Fail 'pubspec.yaml has no version like 1.2.3.' }
$version = $versionLine.Matches[0].Groups[1].Value
$test = [bool]$TestDataDir
$name = if ($test) { 'Dhara-Test' } else { 'Dhara' }
$stage = Join-Path $root "dist\$name-$version"

if (-not $Flutter) {
  $found = Get-Command flutter -ErrorAction SilentlyContinue
  if (-not $found) { Fail 'flutter is not on PATH; pass -Flutter <path to flutter.bat>.' }
  $Flutter = $found.Source
}

# --- Build --------------------------------------------------------------------
Step "Building $name $version (release)"
# An incremental build can keep an old icon font, and with it blank icons.
Get-ChildItem '.dart_tool\flutter_build\*\release_bundle_windows-x64_assets.stamp' -ErrorAction SilentlyContinue |
  Remove-Item -Force
$buildArgs = @('build', 'windows', '--release')
if ($test) { $buildArgs += "--dart-define=DHARA_DATA_DIR=$TestDataDir" }
& $Flutter @buildArgs
if ($LASTEXITCODE -ne 0) { Fail 'the build failed.' }
$release = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path "$release\dhara.exe")) { Fail "no dhara.exe in $release." }

# --- Stage --------------------------------------------------------------------
Step "Copying to $stage"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item "$release\*" $stage -Recurse
# A debug build leaves its compiled Dart code (kernel_blob.bin, 80 MB) among
# the assets, and a release build after it copies that along. The release
# runs data\app.so and never reads it.
Remove-Item "$stage\data\flutter_assets\kernel_blob.bin" -ErrorAction SilentlyContinue
# media_kit's ANGLE download carries a zlib.dll that nothing loads (no file
# of the app imports it or names it) and that is a debug build: it needs a
# runtime only a developer's PC has.
Remove-Item "$stage\zlib.dll" -ErrorAction SilentlyContinue

# The C++ runtime the program and the Flutter engine are linked against. It
# goes beside the program, so that no installer of Microsoft's (which needs
# admin rights) has to run on the PC the app is installed on.
$runtime = 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { Fail 'vswhere.exe not found: Visual Studio Build Tools are needed.' }
$vs = & $vswhere -latest -products * -property installationPath
$crt = Get-ChildItem "$vs\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory -ErrorAction SilentlyContinue |
  Sort-Object FullName | Select-Object -Last 1
if (-not $crt) { Fail "no C++ runtime under $vs\VC\Redist." }
foreach ($file in $runtime) {
  $from = Join-Path $crt.FullName $file
  if (-not (Test-Path $from)) { Fail "$file is not in $($crt.FullName)." }
  $signature = Get-AuthenticodeSignature $from
  if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
    Fail "$file is not signed by Microsoft."
  }
  Copy-Item $from $stage
}

# --- Check the bundled libraries ----------------------------------------------
# media_kit's build script checks its download (ANGLE) by MD5 only, and
# libmpv is a build of its own (windows/libmpv.cmake). Every library that
# comes from elsewhere is compared with the SHA-256 that was looked at; a
# library that is not on the list stops the script as well.
Step 'Checking the bundled libraries'
$expected = @{}
foreach ($line in Get-Content (Join-Path $PSScriptRoot 'bundled-libraries.sha256')) {
  if ($line -match '^([0-9a-f]{64})\s+\*?(\S+)$') { $expected[$Matches[2]] = $Matches[1] }
}
# Built here from this repository, or checked above by signature.
$ours = @('dhara.exe') + $runtime +
  (Get-ChildItem $stage -Filter '*_plugin.dll' | ForEach-Object Name)
$wrong = @()
foreach ($file in Get-ChildItem $stage -File | Where-Object { $_.Extension -in '.dll', '.exe' }) {
  if ($ours -contains $file.Name) { continue }
  $hash = (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLower()
  if (-not $expected.ContainsKey($file.Name)) { $wrong += "$($file.Name): not on the list ($hash)" }
  elseif ($expected[$file.Name] -ne $hash) { $wrong += "$($file.Name): is $hash, the list says $($expected[$file.Name])" }
}
if ($wrong) {
  $wrong | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
  # Not left behind to be taken for a folder that passed.
  Remove-Item $stage -Recurse -Force
  Fail ('a bundled library is not the one that was looked at. After a deliberate update ' +
    '(Flutter, media_kit, sqlite3, libmpv) check where the new file comes from, then put its ' +
    'hash into tool/bundled-libraries.sha256.')
}

# --- Installer ----------------------------------------------------------------
Step 'Making the installer (Inno Setup)'
$iscc = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { Fail 'Inno Setup 6 is not installed (winget install --id JRSoftware.InnoSetup -e).' }
$setup = Join-Path $root "dist\$name-Setup-$version.exe"
Remove-Item $setup -ErrorAction SilentlyContinue
$isccArgs = @("/DAppVersion=$version", "/DSourceDir=$stage", "/DOutputDir=$root\dist", '/Qp')
if ($test) { $isccArgs += '/DTestCopy' }
& $iscc @isccArgs (Join-Path $root 'installer\dhara.iss')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $setup)) { Fail 'Inno Setup did not make the installer.' }

# --- Checksum -----------------------------------------------------------------
# In the form `sha256sum -c` reads. It says that the installer is the file
# this script made, not that the PC it was made on can be trusted.
$hash = (Get-FileHash $setup -Algorithm SHA256).Hash.ToLower()
Set-Content "$setup.sha256" "$hash *$(Split-Path -Leaf $setup)" -Encoding ascii

Step 'Done'
Write-Host ("  folder:    {0} ({1} MB, {2} files)" -f $stage, (SizeMb $stage), (Get-ChildItem $stage -Recurse -File).Count)
Write-Host ("  installer: {0} ({1} MB)" -f $setup, [math]::Round((Get-Item $setup).Length / 1MB, 1))
Write-Host "  sha-256:   $hash"
Write-Host '  to check:  (Get-FileHash <installer> -Algorithm SHA256).Hash'
