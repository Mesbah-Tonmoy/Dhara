import 'dart:async';

import 'package:dhara/core/net/safe_http_client.dart';
import 'package:flutter/widgets.dart';

/// What asking a server for one video found, just now.
@immutable
class CopyProbe {
  const CopyProbe({
    required this.url,
    this.time,
    this.address,
    this.problem,
    this.blocked = false,
    this.refused = false,
  });

  /// The address that was asked for.
  final Uri url;

  /// How long the server took to answer (redirects included): the copy's
  /// live "ping". `null` if it did not answer in time, or not at all.
  final Duration? time;

  /// Where the video really is, after any redirects: what the player is
  /// given.
  final Uri? address;

  /// Why the video cannot be played from there, in plain English; `null`
  /// when it can.
  final String? problem;

  /// The server sends the video somewhere the app may not go (see
  /// `SafeHttpClient`): it must not be opened, not even unchecked.
  final bool blocked;

  /// The server wants a sign-in for it (401 or 403): for a media server,
  /// the session it was asked with is no longer taken.
  final bool refused;

  /// The server answered, and has the video.
  bool get ok => problem == null && time != null && address != null;
}

/// Gives the pages what they ask servers for copies with. Without it, or
/// with [make] left out (tests), nothing is asked and the pages show how
/// the servers answered their last test instead.
class CopyProbeScope extends InheritedWidget {
  const CopyProbeScope({super.key, required this.make, required super.child});

  /// Makes a prober that may ask the configured sources; whoever takes
  /// one closes it.
  final CopyProber Function()? make;

  static CopyProber? newProber(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CopyProbeScope>()?.make?.call();

  @override
  bool updateShouldNotify(CopyProbeScope old) => false;
}

/// Asks the servers for videos, all at once: the live ping of smart
/// playback.
///
/// Each video costs one small request (the first byte of the file is asked
/// for, and the connection is dropped once the answer's head is in), sent
/// through `SafeHttpClient`, so only to hosts [isAllowedHost] lets
/// through, with redirects followed under the app's rules.
class CopyProber {
  CopyProber({
    required bool Function(String host) isAllowedHost,
    this.timeout = const Duration(seconds: 2),
  }) : _client = SafeHttpClient(isAllowedHost: isAllowedHost, timeout: timeout);

  /// How long a server has to answer.
  final Duration timeout;
  final SafeHttpClient _client;

  /// Asks for every one of [urls] at the same time and reports each as
  /// soon as its server has answered, so the fastest comes first. Never
  /// fails: what went wrong is in the [CopyProbe].
  ///
  /// [headers] are the request headers of the addresses that need any (a
  /// media server's session, see `MediaSessions`); they go to the host of
  /// that address only, not to where it redirects.
  Stream<CopyProbe> probe(
    Iterable<Uri> urls, {
    Map<Uri, Map<String, String>> headers = const {},
  }) {
    final results = StreamController<CopyProbe>();
    final list = urls.toSet();
    var left = list.length;
    if (left == 0) {
      unawaited(results.close());
      return results.stream;
    }
    for (final url in list) {
      unawaited(
        probeOne(url, headers: headers[url] ?? const {}).then((result) {
          if (!results.isClosed) results.add(result);
          if (--left == 0) unawaited(results.close());
        }),
      );
    }
    return results.stream;
  }

  /// Asks for one video. Never throws.
  Future<CopyProbe> probeOne(
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    try {
      final answer = await _client.probe(url, headers: headers);
      final problem = switch (answer.statusCode) {
        200 || 206 => null,
        404 || 410 => 'The video is not on the server any more.',
        401 || 403 => 'The server does not let this video be played.',
        final status => 'The server answered $status.',
      };
      return CopyProbe(
        url: url,
        time: answer.responseTime,
        address: answer.url,
        problem: problem,
        refused: answer.statusCode == 401 || answer.statusCode == 403,
      );
    } on SafeHttpException catch (error) {
      return switch (error.failure) {
        SafeHttpFailure.blockedRedirect => CopyProbe(
          url: url,
          blocked: true,
          problem:
              'The server redirects this video to an address that is not '
              'one of your sources.',
        ),
        SafeHttpFailure.tooManyRedirects => CopyProbe(
          url: url,
          blocked: true,
          problem: 'The server keeps redirecting this video.',
        ),
        SafeHttpFailure.timeout => CopyProbe(
          url: url,
          problem: 'The server did not answer in time.',
        ),
        _ => CopyProbe(url: url, problem: 'The server could not be reached.'),
      };
    } on Object {
      return CopyProbe(url: url, problem: 'The server could not be reached.');
    }
  }

  /// Drops every request still running.
  void close() => _client.close();
}
