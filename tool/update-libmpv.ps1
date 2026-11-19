# Takes the newest libmpv build: finds it, downloads it, checks it against
# the SHA-256 GitHub publishes for it, writes the new pin, and runs the tests
# that drive the real library.
#
#   pwsh tool/update-libmpv.ps1 -Check       only says whether there is a newer build
#   pwsh tool/update-libmpv.ps1              takes it, builds, tests
#   pwsh tool/update-libmpv.ps1 -Flutter D:\dev\flutter\bin\flutter.bat
#   pwsh tool/update-libmpv.ps1 -SkipBuild   writes the pin, leaves build and tests to you
#
# It changes windows/libmpv.cmake, one line of tool/bundled-libraries.sha256
# and the three places in the docs that name the build, and keeps the archive
# in windows/libmpv/ (not in git). It commits nothing: look at `git diff`, go
# through docs/manual-test.bn.md with a build, then commit.
#
# Why and when: "Keeping the player up to date" in README.md.
[CmdletBinding()]
param(
  [string]$Flutter,
  [switch]$Check,
  [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Fail([string]$message) { Write-Host "update-libmpv: $message" -ForegroundColor Red; exit 1 }
function Step([string]$message) { Write-Host "== $message" -ForegroundColor Cyan }
function Sha256([string]$path) { (Get-FileHash $path -Algorithm SHA256).Hash.ToLower() }

$repo = 'shinchiro/mpv-winbuild-cmake'
$agent = 'dhara-update-libmpv'
# Not the "v3" archive, which only runs on newer processors.
$archivePattern = '^mpv-dev-x86_64-(\d{8})-git-[0-9a-f]+\.7z$'
$utf8 = New-Object System.Text.UTF8Encoding $false

# --- The build that is pinned -------------------------------------------------
$pinFile = Join-Path $root 'windows\libmpv.cmake'
$pin = [IO.File]::ReadAllText($pinFile)
function PinValue([string]$text, [string]$name) {
  $found = [regex]::Match($text, "set\($name\s+`"([^`"]+)`"\)")
  if (-not $found.Success) { Fail "windows/libmpv.cmake has no $name." }
  $found.Groups[1].Value
}
$oldArchive = PinValue $pin 'DHARA_LIBMPV_ARCHIVE'
$oldSha = PinValue $pin 'DHARA_LIBMPV_SHA256'
if ($oldArchive -notmatch $archivePattern) { Fail "the pinned archive has an unexpected name: $oldArchive" }
$oldDate = [datetime]::ParseExact($Matches[1], 'yyyyMMdd', $null)
$age = [int]([datetime]::Today - $oldDate).TotalDays

# --- The newest build ---------------------------------------------------------
# GitHub's API answers only a few questions an hour from one address, and the
# customers of an ISP often share one; its release page says the same.
function NewestFromApi {
  $release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -UserAgent $agent -TimeoutSec 30
  $asset = $release.assets | Where-Object { $_.name -match $archivePattern } | Select-Object -First 1
  if (-not $asset) { throw 'the newest release has no mpv-dev-x86_64 archive.' }
  if ("$($asset.digest)" -notmatch '^sha256:([0-9a-f]{64})$') { throw 'the API names no SHA-256 for it.' }
  @{ Tag = "$($release.tag_name)"; Name = "$($asset.name)"; Sha256 = $Matches[1] }
}
function NewestFromPage {
  $latest = Invoke-WebRequest "https://github.com/$repo/releases/latest" -UserAgent $agent -TimeoutSec 30
  $tag = $latest.BaseResponse.RequestMessage.RequestUri.Segments[-1]
  $assets = (Invoke-WebRequest "https://github.com/$repo/releases/expanded_assets/$tag" -UserAgent $agent -TimeoutSec 30).Content
  $named = [regex]::Match($assets, 'digest for (mpv-dev-x86_64-\d{8}-git-[0-9a-f]+\.7z)"[^>]*value="sha256:([0-9a-f]{64})"')
  if (-not $named.Success) { throw "the page of release $tag shows no mpv-dev-x86_64 archive with a SHA-256." }
  @{ Tag = $tag; Name = $named.Groups[1].Value; Sha256 = $named.Groups[2].Value }
}

Step 'Asking GitHub for the newest build'
$new = $null
try { $new = NewestFromApi } catch {
  Write-Host "  the API did not help ($($_.Exception.Message.Split("`n")[0])); reading the release page."
  try { $new = NewestFromPage } catch { Fail "could not find the newest build: $($_.Exception.Message)" }
}
if ($new.Tag -notmatch '^\d{8}$') { Fail "the newest release has an unexpected tag: $($new.Tag)" }
if ($new.Name -notmatch $archivePattern) { Fail "the newest archive has an unexpected name: $($new.Name)" }

Write-Host "  pinned: $oldArchive ($age days old)"
Write-Host "  newest: $($new.Name)"
if ($new.Name -eq $oldArchive) {
  if ($new.Sha256 -ne $oldSha) { Fail 'the same archive name has another SHA-256 on GitHub now. Do not go on until that is understood.' }
  Write-Host '  The pinned build is the newest. Nothing to do.' -ForegroundColor Green
  exit 0
}
if ($Check) {
  Write-Host '  There is a newer build. Run this script without -Check to take it.' -ForegroundColor Yellow
  exit 0
}

# --- Download and check -------------------------------------------------------
$cache = Join-Path $root 'windows\libmpv'
New-Item -ItemType Directory -Force $cache | Out-Null
$archive = Join-Path $cache $new.Name
if ((Test-Path $archive) -and (Sha256 $archive) -eq $new.Sha256) {
  Step 'The archive is here already'
} else {
  Step "Downloading $($new.Name)"
  $part = "$archive.part"
  Invoke-WebRequest "https://github.com/$repo/releases/download/$($new.Tag)/$($new.Name)" -OutFile $part -UserAgent $agent
  $got = Sha256 $part
  if ($got -ne $new.Sha256) {
    Remove-Item $part -Force
    Fail "what arrived has the SHA-256 $got, GitHub says $($new.Sha256). Nothing was changed."
  }
  Move-Item $part $archive -Force
}

# --- The library inside -------------------------------------------------------
Step 'Reading libmpv-2.dll from the archive'
# Windows' own tar reads 7z archives, as CMake does when the app is built.
$tar = Join-Path $env:SystemRoot 'System32\tar.exe'
if (-not (Test-Path $tar)) { Fail "no tar.exe in $env:SystemRoot\System32." }
$work = Join-Path ([IO.Path]::GetTempPath()) ("dhara-libmpv-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null
try {
  & $tar -xf $archive -C $work 'libmpv-2.dll'
  $dll = Join-Path $work 'libmpv-2.dll'
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $dll)) { Fail 'the archive holds no libmpv-2.dll that could be read.' }
  $newDllSha = Sha256 $dll
  $newVersion = (Get-Item $dll).VersionInfo.ProductVersion
} finally {
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
if ("$newVersion" -notmatch '^v\d') { Fail "libmpv-2.dll has an unexpected version stamp: $newVersion" }
Write-Host "  mpv $newVersion"

# --- Write the pin ------------------------------------------------------------
Step 'Writing the new pin'
$nextPin = $pin.Replace("set(DHARA_LIBMPV_ARCHIVE `"$oldArchive`")", "set(DHARA_LIBMPV_ARCHIVE `"$($new.Name)`")")
$nextPin = [regex]::Replace($nextPin, '(?<=releases/download/)\d{8}(?=/\$\{DHARA_LIBMPV_ARCHIVE\})', $new.Tag)
$nextPin = $nextPin.Replace($oldSha, $new.Sha256)
if ((PinValue $nextPin 'DHARA_LIBMPV_ARCHIVE') -ne $new.Name -or
    (PinValue $nextPin 'DHARA_LIBMPV_SHA256') -ne $new.Sha256 -or
    (PinValue $nextPin 'DHARA_LIBMPV_URL') -notmatch "/download/$($new.Tag)/") {
  Fail 'windows/libmpv.cmake is not laid out as this script expects. Nothing was changed.'
}

$listFile = Join-Path $root 'tool\bundled-libraries.sha256'
$list = [IO.File]::ReadAllText($listFile)
$listed = [regex]::Match($list, '(?m)^([0-9a-f]{64})(?= \*libmpv-2\.dll\r?$)')
if (-not $listed.Success) { Fail 'tool/bundled-libraries.sha256 has no line for libmpv-2.dll. Nothing was changed.' }
$oldDllSha = $listed.Groups[1].Value

[IO.File]::WriteAllText($pinFile, $nextPin, $utf8)
Write-Host '  windows/libmpv.cmake'
[IO.File]::WriteAllText($listFile, $list.Replace($oldDllSha, $newDllSha), $utf8)
Write-Host '  tool/bundled-libraries.sha256'

# The docs name the build in three places: the table of bundled libraries
# and the version stamp in the two READMEs.
$review = [IO.File]::ReadAllText((Join-Path $root 'docs\security-review.md'))
$stamp = [regex]::Match($review, '`libmpv-2\.dll` \(mpv (v[^,\s]+),')
$oldVersion = if ($stamp.Success) { $stamp.Groups[1].Value } else { $null }
foreach ($doc in 'docs\security-review.md', 'README.md', 'README.bn.md') {
  $path = Join-Path $root $doc
  $text = [IO.File]::ReadAllText($path)
  $next = $text.Replace($oldArchive, $new.Name).Replace($oldDllSha, $newDllSha)
  if ($oldVersion) { $next = $next.Replace($oldVersion, $newVersion) }
  if ($next -ne $text) {
    [IO.File]::WriteAllText($path, $next, $utf8)
    Write-Host "  $($doc.Replace('\', '/'))"
  }
}
if (-not $oldVersion) { Write-Host '  (the docs name no version stamp this script knows: put the new one in by hand)' -ForegroundColor Yellow }

$back = 'git checkout -- windows/libmpv.cmake tool/bundled-libraries.sha256 docs/security-review.md README.md README.bn.md'

# --- Build and test -----------------------------------------------------------
if ($SkipBuild) {
  Step 'Done, without build and tests'
  Write-Host '  Still to do: flutter build windows --release, then flutter test.'
} else {
  if (-not $Flutter) {
    $found = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $found) { Fail "flutter is not on PATH; pass -Flutter <path to flutter.bat>. The pin is written; to go back: $back" }
    $Flutter = $found.Source
  }
  Step 'Building the app with it (release)'
  & $Flutter build windows --release
  if ($LASTEXITCODE -ne 0) { Fail "the build failed. To go back: $back" }
  $built = Join-Path $root 'build\windows\x64\runner\Release\libmpv-2.dll'
  if (-not (Test-Path $built) -or (Sha256 $built) -ne $newDllSha) {
    Fail "the build does not hold the new libmpv-2.dll. To go back: $back"
  }

  # These drive the real library: every hardening option set and read back,
  # mpv's own scripts off, no redirect followed, no file of this PC opened
  # by a playlist, and a video played.
  Step 'Running the tests against the new library'
  & $Flutter test test/features/player/libmpv_hardening_test.dart test/security/code_rules_test.dart
  if ($LASTEXITCODE -ne 0) {
    Fail ('a test failed with the new library: an option changed its name or meaning, or mpv does ' +
      "something new by itself. Do not ship it until that is understood. To go back: $back")
  }
  Step 'Done'
}
Write-Host "  libmpv: $oldArchive -> $($new.Name)"
Write-Host "  mpv:    $newVersion"
Write-Host '  Next: flutter test (all of it), a build tried by hand (docs/manual-test.bn.md), then commit:'
Write-Host "    chore(player): libmpv $newVersion"
