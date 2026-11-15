import 'package:dhara/core/net/safe_http_client.dart';

/// A video that must not be opened: its server sends the player somewhere
/// the app is not allowed to go.
class PlaybackBlocked implements Exception {
  const PlaybackBlocked(this.message);

  /// Plain English, safe to show.
  final String message;

  @override
  String toString() => 'PlaybackBlocked: $message';
}

/// Where the player should fetch [url] from.
///
/// libmpv's HTTP code (FFmpeg) follows redirects on its own, to any http(s)
/// host, and the bundled build has no option to stop that. So the app
/// follows them first, under its own rules ([client] only allows the host
/// that was asked for and the configured sources), and hands the player
/// the address at the end of the chain, which normally redirects no
/// further.
///
/// Throws [PlaybackBlocked] if the chain leaves the allowed hosts or does
/// not end. If the server cannot be asked at all (unreachable, too slow),
/// [url] is returned as it is: the player then reports the real problem.
///
/// [onAnswered] is told how long the server took to answer (redirects
/// included), if it did.
Future<Uri> resolvePlaybackUrl(
  SafeHttpClient client,
  Uri url, {
  void Function(Duration time)? onAnswered,
}) async {
  try {
    final answer = await client.probe(url);
    onAnswered?.call(answer.responseTime);
    return answer.url;
  } on SafeHttpException catch (error) {
    switch (error.failure) {
      case SafeHttpFailure.blockedRedirect:
        throw const PlaybackBlocked(
          'the server redirects this video to an address that is not one '
          'of your sources, so it was not opened.',
        );
      case SafeHttpFailure.tooManyRedirects:
        throw const PlaybackBlocked(
          'the server keeps redirecting this video, so it was not opened.',
        );
      // (A URL with a user name in it cannot be asked by the app's client.)
      case SafeHttpFailure.blockedUrl:
      case SafeHttpFailure.timeout:
      case SafeHttpFailure.network:
      case SafeHttpFailure.tooLarge:
        return url;
    }
  }
}
