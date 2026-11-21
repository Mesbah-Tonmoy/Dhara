import 'package:dhara/features/sources/adapters/adapter_factory.dart';
import 'package:dhara/features/sources/adapters/directory_listing_adapter.dart';
import 'package:dhara/features/sources/adapters/emby_adapter.dart';
import 'package:dhara/features/sources/adapters/flixhub_adapter.dart';
import 'package:dhara/features/sources/adapters/h5ai_adapter.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/local_server.dart';

void main() {
  late LocalServer server;

  setUp(() async => server = await LocalServer.start());
  tearDown(() => server.close());

  SourceAdapter? make(SourceType type, {String deviceId = 'dhara-test'}) =>
      adapterFor(
        type,
        server.client(),
        baseUrl: server.url('/'),
        deviceId: deviceId,
      );

  test('every source type gets its adapter', () {
    expect(make(SourceType.directoryListing), isA<DirectoryListingAdapter>());
    expect(make(SourceType.h5ai), isA<H5aiAdapter>());
    expect(make(SourceType.emby), isA<EmbyAdapter>());
    expect(make(SourceType.jellyfin), isA<EmbyAdapter>());
    expect(make(SourceType.flixHub), isA<FlixHubAdapter>());
  });

  test('a custom website has no adapter', () {
    expect(make(SourceType.customSite), isNull);
  });

  test('the adapter reads through the client it was given', () async {
    server.serve('/DHAKA-FLIX-7/', fixture('listings/h5ai_root.html'));

    final entries = await make(
      SourceType.h5ai,
    )!.list(server.url('/DHAKA-FLIX-7/'));

    expect(entries.first.url, server.url('/DHAKA-FLIX-7/3D%20Movies/'));
    expect(server.requests, hasLength(1));
  });

  test('an Emby adapter refuses a device id that could break a header', () {
    expect(
      () => make(SourceType.emby, deviceId: 'bad"id'),
      throwsArgumentError,
    );
  });
}
