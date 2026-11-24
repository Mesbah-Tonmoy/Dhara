# Shared by tool/package.ps1 and tool/sign-update.ps1 (dot-sourced).

# The address a program can fetch a file from, out of the link a person was
# given for it: a Google Drive link of any of its shapes becomes the address
# that answers with the file itself (a plain download link of Drive answers
# a large file with a page that asks to confirm); anything else has to be an
# https address without a user name. $null if it is neither.
function DownloadAddress([string]$link) {
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

# Whether $path lies inside $folder.
function IsInside([string]$path, [string]$folder) {
  $full = [IO.Path]::GetFullPath($path)
  $base = [IO.Path]::GetFullPath($folder).TrimEnd('\') + '\'
  return $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)
}
