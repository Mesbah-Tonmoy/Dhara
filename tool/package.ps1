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
# Without -Dev it makes the production build, which is ready to use and has
# no tools for working on the library. -Dev makes the development build
# (Titles and matching, Library index, the TMDB key): it is called
# "Dhara Dev" and installs beside the production app, never over it. The two
# keep their data in the same folder, so only one of them should be open at
# a time.
#
# -SnapshotUrl <address> is where the production build fetches its library
# from the first time it starts on a PC (the file "Write snapshot" of a
# development build makes). An https address, or the link Google Drive
# gives for a file shared with "anyone with the link": that is turned into
# the address Drive hands the file itself out at. Without it the build
# fetches nothing and has to read the servers itself.
#
# -TmdbKeyFile <file> builds a TMDB key into the production build, so that it
# shows posters and looks up new titles without asking anyone for a key. The
# file holds the key (the API key or the read access token) and nothing
# else, and must lie outside this repository. The key is never printed. It
# becomes part of the program: whoever has the installer can read it out.
# After such a build the script removes what the build left of the key on
# this PC (build\windows, .dart_tool\flutter_build and the generated build
# settings); it stays in dist\, in the folder and the installer made for
# handing out.
#
# -TestDataDir <folder> makes a copy for trying the installer without
# touching the real library: that build keeps its data in <folder>, is called
# "Dhara Test" and installs beside the real app, never over it.
#
# -Logo <name> makes another drawing the logo the installed app starts with
# (water, classic, dark, rounded, darkRounded, darkWater; Settings can still
# change it). -LogoFromSettings takes the one chosen in Settings on this PC.
# Without either it is the app's own default. The program's icon in Windows
# does not follow it.
[CmdletBinding()]
param(
  [string]$Flutter,
  [switch]$Dev,
  [string]$SnapshotUrl,
  [string]$TmdbKeyFile,
  [string]$TestDataDir,
  [string]$Logo,
  [switch]$LogoFromSettings
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# What a build keeps of the values it was given: a TMDB key would lie on in
# these files until the next build. They are all made again by a build.
$script:keyWasBuilt = $false
function ForgetBuiltKey {
  if (-not $script:keyWasBuilt) { return }
  foreach ($left in 'build\windows', '.dart_tool\flutter_build', 'windows\flutter\ephemeral\generated_config.cmake') {
    Remove-Item (Join-Path $root $left) -Recurse -Force -ErrorAction SilentlyContinue
  }
  $script:keyWasBuilt = $false
}
function Fail([string]$message) { ForgetBuiltKey; Write-Host "package: $message" -ForegroundColor Red; exit 1 }
# Also when a step of the script itself breaks.
trap { ForgetBuiltKey; break }
function Step([string]$message) { Write-Host "== $message" -ForegroundColor Cyan }
function SizeMb([string]$path) {
  $bytes = (Get-ChildItem $path -Recurse -File | Measure-Object Length -Sum).Sum
  [math]::Round($bytes / 1MB, 1)
}

# The address a build fetches its snapshot from, out of what was given: a
# Google Drive link of any of its shapes becomes the address that answers
# with the file (a plain download link of Drive answers a large file with a
# page that asks to confirm); anything else has to be an https address.
function SnapshotAddress([string]$link) {
  $link = $link.Trim()
  $id = $null
  if ($link -match '^https://(?:drive|docs)\.google\.com/.*?(?:/d/|[?&]id=)([A-Za-z0-9_-]{10,})') { $id = $Matches[1] }
  elseif ($link -match '^https://drive\.usercontent\.google\.com/.*?[?&]id=([A-Za-z0-9_-]{10,})') { $id = $Matches[1] }
  if ($id) { return "https://drive.usercontent.google.com/download?id=$id&export=download&confirm=t" }
  # A link of Drive that names no file (a folder, the start page).
  if ($link -match '^https://(?:drive|docs)\.google\.com/') { return $null }
  $parsed = $null
  if (-not [uri]::TryCreate($link, [urikind]::Absolute, [ref]$parsed)) { return $null }
  if ($parsed.Scheme -ne 'https' -or -not $parsed.Host -or $parsed.UserInfo) { return $null }
  return $link
}

# --- What is being packaged ---------------------------------------------------
$versionLine = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\d+\.\d+\.\d+)' | Select-Object -First 1
if (-not $versionLine) { Fail 'pubspec.yaml has no version like 1.2.3.' }
$version = $versionLine.Matches[0].Groups[1].Value
$test = [bool]$TestDataDir
# A test copy is made to try the installer, whichever build is inside: one
# name for it is enough.
if ($test -and $Dev) { Fail '-Dev and -TestDataDir cannot be used together.' }
$name = if ($test) { 'Dhara-Test' } elseif ($Dev) { 'Dhara-Dev' } else { 'Dhara' }
$snapshotAddress = $null
if ($SnapshotUrl) {
  if ($Dev) { Fail '-SnapshotUrl is for the production build; a development build fetches no library.' }
  $snapshotAddress = SnapshotAddress $SnapshotUrl
  if (-not $snapshotAddress) { Fail '-SnapshotUrl must be an https address or a Google Drive share link.' }
}

# The TMDB key of a production build: read from a file outside the
# repository, checked for its shape, and never shown.
function TmdbKeyKind([string]$key) {
  if ($key -cmatch '^[0-9a-fA-F]{32}$') { return 'API key' }
  if ($key.Length -ge 80 -and $key.Length -le 1024 -and
      $key -cmatch '^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$') { return 'access token' }
  return $null
}
function IsInside([string]$path, [string]$folder) {
  $full = [IO.Path]::GetFullPath($path)
  $base = [IO.Path]::GetFullPath($folder).TrimEnd('\') + '\'
  return $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)
}
$tmdbKey = $null
if ($TmdbKeyFile) {
  if ($Dev) { Fail '-TmdbKeyFile is for the production build; a development build asks for the key in Settings.' }
  if (-not (Test-Path $TmdbKeyFile -PathType Leaf)) { Fail '-TmdbKeyFile names no file.' }
  if (IsInside $TmdbKeyFile $root) { Fail 'the file with the TMDB key must lie outside this repository.' }
  $tmdbKey = (Get-Content $TmdbKeyFile -Raw).Trim()
  $tmdbKeyKind = TmdbKeyKind $tmdbKey
  if (-not $tmdbKeyKind) { Fail 'the file does not hold a TMDB key (32 letters and digits) or a TMDB read access token, alone.' }
}
$stage = Join-Path $root "dist\$name-$version"

if (-not $Flutter) {
  $found = Get-Command flutter -ErrorAction SilentlyContinue
  if (-not $found) { Fail 'flutter is not on PATH; pass -Flutter <path to flutter.bat>.' }
  $Flutter = $found.Source
}

# --- The logo it starts with --------------------------------------------------
if ($LogoFromSettings -and -not $Logo) {
  $settings = Join-Path $env:APPDATA 'com.dhara\dhara\shared_preferences.json'
  if (Test-Path $settings) { $Logo = (Get-Content $settings -Raw | ConvertFrom-Json).'flutter.look.logo' }
  if (-not $Logo) { Write-Host '  No logo is chosen in Settings on this PC; the default stays.' }
}
if ($Logo) {
  # The names are those of the drawings in the code.
  $drawings = Select-String -Path lib\theme\logo_style.dart -Pattern "^\s+(\w+)\('" |
    ForEach-Object { $_.Matches[0].Groups[1].Value }
  if ($drawings -cnotcontains $Logo) { Fail "there is no logo called '$Logo' (there are: $($drawings -join ', '))." }
}

# --- Build --------------------------------------------------------------------
Step "Building $name $version (release)"
# An incremental build can keep an old icon font, and with it blank icons.
Get-ChildItem '.dart_tool\flutter_build\*\release_bundle_windows-x64_assets.stamp' -ErrorAction SilentlyContinue |
  Remove-Item -Force
$buildArgs = @('build', 'windows', '--release')
if ($Dev) { $buildArgs += '--dart-define=DHARA_DEV=true' }
if ($test) { $buildArgs += "--dart-define=DHARA_DATA_DIR=$TestDataDir" }
if ($Logo) { $buildArgs += "--dart-define=DHARA_LOGO=$Logo"; Write-Host "  logo: $Logo" }
# The address and the key go to the build in a file: the address holds "&",
# which a command line would cut it at, and a key on a command line can be
# read by every program of this user. The file lies outside the repository
# and is removed.
$given = @{}
if ($snapshotAddress) {
  $given.DHARA_SNAPSHOT_URL = $snapshotAddress
  Write-Host "  library from: $snapshotAddress"
} elseif (-not $Dev) {
  Write-Host '  No -SnapshotUrl: this build fetches no library and has to read the servers itself.' -ForegroundColor Yellow
}
if ($tmdbKey) {
  $given.DHARA_TMDB_KEY = $tmdbKey
  Write-Host "  TMDB key: built in (a TMDB $tmdbKeyKind, from a file outside the repository)"
} elseif (-not $Dev) {
  Write-Host '  No -TmdbKeyFile: this build looks nothing up on TMDB unless a key is saved on the PC it runs on.' -ForegroundColor Yellow
}
$defines = $null
if ($given.Count -gt 0) {
  $defines = Join-Path ([IO.Path]::GetTempPath()) "dhara-defines-$([guid]::NewGuid().ToString('N')).json"
  [IO.File]::WriteAllText($defines, ($given | ConvertTo-Json))
  $buildArgs += "--dart-define-from-file=$defines"
}
try {
  if ($tmdbKey) { $script:keyWasBuilt = $true }
  & $Flutter @buildArgs
} finally {
  if ($defines) { Remove-Item $defines -Force -ErrorAction SilentlyContinue }
}
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

# The staged folder has what it needs; nothing of the key stays in the
# build's own files.
ForgetBuiltKey
$tmdbKey = $null; $given = $null

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
if ($Dev) { $isccArgs += '/DDevCopy' }
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
