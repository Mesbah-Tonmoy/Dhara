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
