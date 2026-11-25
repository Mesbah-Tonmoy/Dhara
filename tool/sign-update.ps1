# Signs an update, so that installed copies of Dhara will take it, and makes
# the key pair that is needed for it once.
#
# An installed production build asks one address for an "update notice": a
# small file that names the newest version, where its installer lies, how
# large it is and its SHA-256, signed with a key only you have. The app
# believes a notice only if the signature fits the public half of that key,
# which it was built with, and starts an installer only if it is the very
# file the notice names. This script makes that notice.
#
# Once, on a PC you trust:
#
#   pwsh tool/sign-update.ps1 -NewKey D:\keys\dhara-update
#
# writes D:\keys\dhara-update.private.pem (the private half: whoever has it
# can make updates every installed copy takes, so it never goes into the
# repository, an installer or a chat; keep a copy somewhere safe) and
# D:\keys\dhara-update.public.txt (the public half, no secret: give it to
# tool/package.ps1 -UpdateKeyFile). The private half is written as it is, not
# encrypted: keep it on a drive that is.
#
# For every release, after tool/package.ps1 made the installer and you put
# it where the app can fetch it:
#
#   pwsh tool/sign-update.ps1 -Installer dist\Dhara-Setup-1.2.0.exe `
#     -InstallerLink "<the link to the uploaded installer>" `
#     -KeyFile D:\keys\dhara-update.private.pem -Notes "What is new."
#
# writes dist\dhara-update.json. Put that file where the app asks (the
# address given to tool/package.ps1 -UpdateUrl), replacing the one before.
# -InstallerLink is an https address or a Google Drive share link, as for
# -SnapshotUrl; the installer has to lie on the same host as the notice.
# The version is read from the installer; -Version says it if that fails.
#
# Before it signs, the script fetches what lies at -InstallerLink once and
# holds it against the installer (length and SHA-256), so that a wrong link
# or an upload of another build is found here and not by every installed
# copy. -NoCheck leaves that out, for a PC without a connection.
#
# Nothing is uploaded and nothing but the files named above is written. The
# private key is never printed.
[CmdletBinding(DefaultParameterSetName = 'Sign')]
param(
  [Parameter(ParameterSetName = 'NewKey', Mandatory)][string]$NewKey,
  [Parameter(ParameterSetName = 'Sign', Mandatory)][string]$Installer,
  [Parameter(ParameterSetName = 'Sign', Mandatory)][string]$InstallerLink,
  [Parameter(ParameterSetName = 'Sign', Mandatory)][string]$KeyFile,
  [Parameter(ParameterSetName = 'Sign')][string]$Version,
  [Parameter(ParameterSetName = 'Sign')][string]$Notes,
  [Parameter(ParameterSetName = 'Sign')][string]$Out,
  [Parameter(ParameterSetName = 'Sign')][switch]$NoCheck
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'download-address.ps1')

function Fail([string]$message) { Write-Host "sign-update: $message" -ForegroundColor Red; exit 1 }
# A path as given on the command line, whole: counted from the folder the
# shell is in, whether or not anything is there yet.
function FullPath([string]$path) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path) }
if ($PSVersionTable.PSVersion.Major -lt 7) { Fail 'this needs PowerShell 7 (pwsh), not Windows PowerShell.' }

$sha256 = [Security.Cryptography.HashAlgorithmName]::SHA256
# The public half as the app takes it: X and Y of the point, 64 bytes, in
# base64.
function PublicText([Security.Cryptography.ECDsa]$key) {
  $point = $key.ExportParameters($false).Q
  [Convert]::ToBase64String([byte[]]($point.X + $point.Y))
}

# --- A new key pair -----------------------------------------------------------
if ($NewKey) {
  $base = FullPath $NewKey
  if (IsInside $base $root) { Fail 'the key must lie outside this repository.' }
  $privateFile = "$base.private.pem"
  $publicFile = "$base.public.txt"
  foreach ($file in $privateFile, $publicFile) {
    if (Test-Path $file) { Fail "$file is there already. A key that is replaced cannot sign for the copies built with it." }
  }
  $folder = Split-Path -Parent $base
  if (-not (Test-Path $folder -PathType Container)) { Fail "there is no folder $folder." }

  $key = [Security.Cryptography.ECDsa]::Create([Security.Cryptography.ECCurve]::CreateFromFriendlyName('nistP256'))
  try {
    $pem = $key.ExportPkcs8PrivateKeyPem()
    [IO.File]::WriteAllText($privateFile, $pem + "`n")
    $pem = $null
    [IO.File]::WriteAllText($publicFile, (PublicText $key) + "`n")
  } finally { $key.Dispose() }

  Write-Host "  private half: $privateFile" -ForegroundColor Cyan
  Write-Host '                keep it out of the repository, out of chats and off shared folders;'
  Write-Host '                keep a copy somewhere safe: without it no installed copy can be updated from inside.'
  Write-Host '                it is not encrypted: keep it on a drive that is.' -ForegroundColor Yellow
  Write-Host "  public half:  $publicFile" -ForegroundColor Cyan
  Write-Host '                give it to: pwsh tool/package.ps1 -UpdateKeyFile <that file> -UpdateUrl <link of the notice>'
  exit 0
}

# --- Signing an installer -----------------------------------------------------
if (-not (Test-Path $Installer -PathType Leaf)) { Fail '-Installer names no file.' }
$installerFile = Get-Item (Resolve-Path $Installer)
if (-not (Test-Path $KeyFile -PathType Leaf)) { Fail '-KeyFile names no file.' }
if (IsInside (FullPath $KeyFile) $root) { Fail 'the private key must lie outside this repository.' }

$address = DownloadAddress $InstallerLink
if (-not $address) { Fail '-InstallerLink must be an https address or a Google Drive share link of the installer.' }

# Inno Setup writes the version it was given into the installer.
$inFile = $null
if ($installerFile.VersionInfo.FileVersion -match '^\s*(\d+\.\d+\.\d+)(\.\d+)?\s*$') { $inFile = $Matches[1] }
if (-not $Version) {
  if (-not $inFile) { Fail 'the installer does not say its version; pass -Version <x.y.z>.' }
  $Version = $inFile
} elseif ($inFile -and $inFile -ne $Version) {
  # Allowed, for trying things; a real release names the installer's own.
  Write-Host "  The installer says it is $inFile; the notice will say $Version." -ForegroundColor Yellow
}
if ($Version -notmatch '^\d{1,5}\.\d{1,5}\.\d{1,5}$') { Fail '-Version must look like 1.2.3.' }
if ($Notes -and $Notes.Length -gt 4000) { Fail '-Notes may be 4000 characters at most.' }

# What is signed: these lines as bytes, exactly as they are written here.
# The app checks the signature over the bytes before it reads them.
$told = [ordered]@{
  version   = $Version
  installer = $address
  size      = $installerFile.Length
  sha256    = (Get-FileHash $installerFile.FullName -Algorithm SHA256).Hash.ToLower()
}
if ($Notes) { $told.notes = $Notes }

# What lies at the link has to be this very installer: a notice that names
# another file (the link of the notice itself, an installer that was built
# anew after the upload) is one every copy refuses. So the file is fetched
# once, the way the app will fetch it (no cookie, no redirect followed),
# and hashed as it comes. Nothing is saved, and nothing is signed if it is
# not the installer.
if (-not $NoCheck) {
  Write-Host '  Checking what lies at the link ...'
  $found = @{ Length = 0L; Sha256 = $null; Name = $null; Problem = $null }
  $handler = [Net.Http.HttpClientHandler]::new()
  $handler.AllowAutoRedirect = $false
  $handler.UseCookies = $false
  $client = [Net.Http.HttpClient]::new($handler)
  $client.Timeout = [TimeSpan]::FromMinutes(20)
  try {
    $response = $client.GetAsync($address, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    $status = [int]$response.StatusCode
    $type = [string]$response.Content.Headers.ContentType
    if ($status -ge 300 -and $status -lt 400) { $found.Problem = 'it answers by sending on to another address, which the app does not follow' }
    elseif ($status -ne 200) { $found.Problem = "the place answers $status" }
    elseif ($type -like 'text/*') { $found.Problem = 'a page comes in place of the file: is it shared with "anyone with the link"?' }
    else {
      $disposition = $response.Content.Headers.ContentDisposition
      if ($disposition) { $found.Name = ([string]$disposition.FileName).Trim('"') }
      $hash = [Security.Cryptography.IncrementalHash]::CreateHash($sha256)
      $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
      $buffer = [byte[]]::new(1MB)
      # Not a byte more than it takes to know that it is another file.
      while ($found.Length -le $told.size -and ($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $hash.AppendData($buffer, 0, $read)
        $found.Length += $read
      }
      $found.Sha256 = [Convert]::ToHexString($hash.GetHashAndReset()).ToLower()
      $hash.Dispose()
    }
  } catch {
    $found.Problem = 'the place did not answer'
  } finally { $client.Dispose() }
  if ($found.Problem) {
    Fail "the installer could not be fetched from -InstallerLink ($($found.Problem)). Nothing was signed. (-NoCheck signs without looking.)"
  }
  if ($found.Length -ne $told.size -or $found.Sha256 -ne $told.sha256) {
    $what = if ($found.Length -gt $told.size) { "more than $($told.size) bytes" } else { "$($found.Length) bytes" }
    if ($found.Name) { $what = "'$($found.Name)', $what" }
    Fail ("what lies at -InstallerLink is not this installer: there it is $what; the installer is $($told.size) bytes. " +
      'Give the link of the uploaded installer (not the link of the notice), and upload the installer again if it was built anew. Nothing was signed.')
  }
  Write-Host '  It is this installer.' -ForegroundColor Green
}
$signed =[Text.UTF8Encoding]::new($false).GetBytes(($told | ConvertTo-Json -Compress))

$pem = (Get-Content $KeyFile -Raw)
$key = [Security.Cryptography.ECDsa]::Create()
try {
  try {
    if ($pem -notmatch 'BEGIN (EC )?PRIVATE KEY') {
      Fail '-KeyFile does not hold a private key (the .private.pem file -NewKey wrote).'
    }
    $key.ImportFromPem($pem)
  } catch {
    Fail 'the private key could not be read (a damaged file).'
  } finally { $pem = $null }
  if ($key.KeySize -ne 256) { Fail 'the key is not a P-256 key.' }

  # r and s, 32 bytes each: the form the app checks.
  $signature = $key.SignData($signed, $sha256)
  if ($signature.Length -ne 64 -or -not $key.VerifyData($signed, $signature, $sha256)) {
    Fail 'the signature that was made does not fit; nothing was written.'
  }
  $public = PublicText $key
} finally { $key.Dispose() }

$notice = [ordered]@{
  dhara_update = 1
  signed       = [Convert]::ToBase64String($signed)
  signature    = [Convert]::ToBase64String($signature)
} | ConvertTo-Json
if (-not $Out) { $Out = Join-Path $root 'dist\dhara-update.json' }
$Out = FullPath $Out
New-Item -ItemType Directory -Force (Split-Path -Parent $Out) | Out-Null
[IO.File]::WriteAllText($Out, $notice + "`n", [Text.UTF8Encoding]::new($false))

Write-Host "  notice:     $Out" -ForegroundColor Cyan
Write-Host "  version:    $Version"
Write-Host ("  installer:  {0} ({1} MB)" -f $installerFile.Name, [math]::Round($installerFile.Length / 1MB, 1))
Write-Host "  sha-256:    $($told.sha256)"
Write-Host "  fetched at: $address"
Write-Host "  signed for: $public"
Write-Host '              (the public half: the copies built with it take this notice)'
Write-Host ("  Now put the notice where the app asks. It must be on the host the installer is on ({0})." -f ([uri]$address).Host)
