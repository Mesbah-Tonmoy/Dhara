/// URL schemes the app is allowed to open (BRIEF section 7).
const allowedUrlSchemes = <String>{'http', 'https'};

/// Parses pasted or server-supplied text into a playable media URL.
///
/// Returns `null` unless the text is an absolute `http`/`https` URL with a
/// host. Everything else (`file://`, `smb://`, mpv pseudo-protocols such as
/// `edl://` or `memory://`, relative paths) is rejected, so nothing but a
/// plain web URL ever reaches the player.
///
/// Private IP ranges are deliberately allowed: many BDIX servers live on
/// 10.x or 172.16.x addresses.
Uri? parseMediaUrl(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (!allowedUrlSchemes.contains(uri.scheme)) return null;
  if (uri.host.isEmpty) return null;
  return uri;
}

/// A display title for [url]: the decoded file name, or the host when the
/// path has none. The result is server-controlled text, so only ever show it
/// through a plain `Text` widget.
String mediaTitleFromUrl(Uri url) {
  final rawSegments = url.path.split('/').where((s) => s.isNotEmpty).toList();
  if (rawSegments.isEmpty) return url.host;

  final raw = rawSegments.last;
  try {
    return Uri.decodeComponent(raw);
  } on FormatException {
    // Percent-escapes that are not valid UTF-8 (old servers, legacy
    // encodings): fall back to the raw text instead of failing.
    return raw;
  } on ArgumentError {
    // Malformed escape sequence.
    return raw;
  }
}
