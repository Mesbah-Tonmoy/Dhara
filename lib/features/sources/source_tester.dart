import 'dart:async';

import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/sources/adapters/directory_listing_adapter.dart';
import 'package:dhara/features/sources/adapters/emby_adapter.dart';
import 'package:dhara/features/sources/adapters/h5ai_adapter.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:dhara/features/sources/portal_links.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:html/parser.dart' as html;

/// What testing one base URL of a source found.
class UrlTestResult {
  const UrlTestResult({
    required this.url,
    required this.reachable,
    this.ping,
    this.detectedType,
    this.software,
    this.entryCount,
    this.sample = const [],
    this.links = const [],
    this.problem,
  });

  final Uri url;

  /// The server answered, whatever it said.
  final bool reachable;

  /// How long the first answer took (see `SafeHttpResponse.responseTime`).
  final Duration? ping;

  /// What the server turned out to be, whatever the source list claims.
  /// [SourceType.customSite] means "a web page of some other kind".
  final SourceType? detectedType;

  /// The server software if it says, e.g. `nginx/1.12.2` or `Emby 4.8.5.0`.
  final String? software;

  /// How many files and folders the first page lists.
  final int? entryCount;

  /// The first few names found (for a custom site: the page title).
  final List<String> sample;

  /// For a web page of some other kind: the other servers it links to
  /// (see [portalLinks]). They are only named, never asked.
  final List<PortalLink> links;

  /// Why this URL cannot be used, in plain English; `null` when it can.
  final String? problem;

  /// The app can read this URL's content: it answered, an adapter for its
  /// type exists and listing it worked.
  bool get readable =>
      reachable &&
      problem == null &&
      detectedType != null &&
      detectedType != SourceType.customSite;
}

/// What testing a whole source found: one result per base URL.
class SourceTestResult {
  const SourceTestResult({required this.source, required this.urls});

  final Source source;
  final List<UrlTestResult> urls;

  bool get reachable => urls.any((url) => url.reachable);
  bool get readable => urls.any((url) => url.readable);

  /// The fastest answer among the base URLs.
  Duration? get ping {
    Duration? best;
    for (final url in urls) {
      final ping = url.ping;
      if (ping != null && (best == null || ping < best)) best = ping;
    }
    return best;
  }

  /// What the server is, from the first base URL the app could read; `null`
  /// if it could read none. This is what the source's type should be.
  SourceType? get readableType {
    for (final url in urls) {
      if (url.readable) return url.detectedType;
    }
    return null;
  }

  /// The type found, from the first base URL that revealed one.
  SourceType? get detectedType {
    for (final url in urls) {
      if (url.detectedType != null) return url.detectedType;
    }
    return null;
  }
}

/// The BDIX Tester: finds out which sources answer from this connection,
/// how fast, what kind of server each is, and what is on it.
///
/// It only ever contacts the base URLs of the sources it is given (and
/// those servers' own API paths): no port scanning, no address sweeps. A
/// run uses its own HTTP client that knows no other host, so a redirect
/// elsewhere is refused.
class SourceTester {
  SourceTester({
    required this.deviceId,
    this.concurrency = 16,
    this.timeout = const Duration(seconds: 8),
    this.sampleSize = 5,
  }) {
    if (!isValidDeviceId(deviceId)) {
      throw ArgumentError.value(deviceId, 'deviceId', 'letters, digits, "-"');
    }
  }

  /// Passed to Emby/Jellyfin servers when signing in (see `EmbyAdapter`).
  final String deviceId;

  /// How many sources are tested at the same time. The base URLs of one
  /// source are tested one after another, as they are usually one machine.
  /// A test is one small request to a server, and most servers of a long
  /// list do not answer at all, so each of them holds a place for the
  /// whole [timeout]: with few places a long list takes many minutes.
  final int concurrency;

  /// Time limit for each request.
  final Duration timeout;
  final int sampleSize;

  /// Tests [sources] and reports each one as soon as it is done, so the
  /// order is by speed, not list order. Cancelling the subscription stops
  /// the run.
  Stream<SourceTestResult> testAll(Iterable<Source> sources) {
    final list = sources.toList();
    final hosts = {
      for (final source in list)
        for (final url in source.baseUrls) url.host,
    };
    final client = SafeHttpClient(
      isAllowedHost: hosts.contains,
      timeout: timeout,
      maxBytes: _maxTestPageBytes,
    );
    final queue = list.iterator;
    var cancelled = false;
    late final StreamController<SourceTestResult> results;

    Future<void> worker() async {
      while (!cancelled && queue.moveNext()) {
        final result = await _testSource(client, queue.current);
        if (!cancelled) results.add(result);
      }
    }

    results = StreamController(
      onListen: () async {
        await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
        client.close();
        if (!cancelled) await results.close();
      },
      onCancel: () {
        cancelled = true;
        client.close();
      },
    );
    return results.stream;
  }

  Future<SourceTestResult> _testSource(
    SafeHttpClient client,
    Source source,
  ) async {
    final urls = <UrlTestResult>[];
    for (final url in source.baseUrls) {
      urls.add(await _testUrl(client, url));
    }
    return SourceTestResult(source: source, urls: urls);
  }

  Future<UrlTestResult> _testUrl(SafeHttpClient client, Uri url) async {
    final SafeHttpResponse page;
    try {
      page = await client.get(url);
    } on SafeHttpException catch (error) {
      return UrlTestResult(
        url: url,
        // These mean "it answered, but not usefully".
        reachable: const {
          SafeHttpFailure.tooLarge,
          SafeHttpFailure.blockedRedirect,
          SafeHttpFailure.tooManyRedirects,
        }.contains(error.failure),
        problem: error.message,
      );
    }

    final serverHeader = page.header('server');
    var software =
        serverHeader == null ? null : cleanServerText(serverHeader, 60);
    SourceType? type;
    var entries = const <RemoteEntry>[];
    List<String>? sample;
    var links = const <PortalLink>[];
    String? problem;
    try {
      if (!page.isOk) {
        throw SourceReadException('The server answered ${page.statusCode}.');
      }
      final document = html.parse(page.body);
      if (isH5ai(document)) {
        type = SourceType.h5ai;
        entries = parseH5aiListing(page.body, page.url);
      } else if (isDirectoryListing(document)) {
        type = SourceType.directoryListing;
        entries = parseDirectoryListing(page.body, page.url);
      } else {
        final server = await probeMediaServer(client, url);
        if (server == null) {
          type = SourceType.customSite;
          final title = document.querySelector('title')?.text ?? '';
          sample = [if (title.trim().isNotEmpty) cleanServerText(title, 80)];
          links = portalLinks(document, page.url);
        } else {
          type = server.type;
          final product = type == SourceType.jellyfin ? 'Jellyfin' : 'Emby';
          software = '$product ${server.version}';
          entries = await EmbyAdapter(
            client,
            baseUrl: url,
            deviceId: deviceId,
          ).list(url);
        }
      }
    } on SourceReadException catch (error) {
      problem = error.message;
    } on SafeHttpException catch (error) {
      // A follow-up request failed; the server itself did answer.
      problem = error.message;
    } on Exception {
      // Whatever else a strange answer trips over must not end the run.
      problem = 'The answer could not be read.';
    }

    return UrlTestResult(
      url: url,
      reachable: true,
      ping: page.responseTime,
      detectedType: type,
      software: software,
      entryCount: sample == null && problem == null ? entries.length : null,
      sample:
          sample ?? [for (final entry in entries.take(sampleSize)) entry.name],
      links: links,
      problem: problem,
    );
  }
}

// The first page of a source is small; anything bigger is not worth
// reading just to test it.
const _maxTestPageBytes = 1024 * 1024;
