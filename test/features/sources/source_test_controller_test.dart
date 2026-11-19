import 'dart:async';
import 'dart:io';

import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/features/sources/source_tester.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_server.dart';

void main() {
  late LocalServer server;
  late Directory dir;
  late File file;
  var now = DateTime(2026, 11, 13, 9);

  setUp(() async {
    server = await LocalServer.start();
    // "good" is a readable folder listing, "site" answers but is an
    // ordinary page, "dead" answers 404; anything else is 404 too.
    server
      ..serve('/good/', '<title>Index of /good/</title><a href="a.mkv">a</a>')
      ..serve('/site/', '<title>Some site</title>');
    dir = Directory.systemTemp.createTempSync('dhara_controller_test_');
    file = File('${dir.path}/sources.json');
    now = DateTime(2026, 11, 13, 9);
  });

  tearDown(() async {
    await server.close();
    dir.deleteSync(recursive: true);
  });

  Source source(String id, {String? path}) => Source(
        id: id,
        name: id,
        type: SourceType.directoryListing,
        category: SourceCategory.mixed,
        baseUrls: [server.url(path ?? '/$id/')],
      );

  Future<SourceTestController> open({List<String> ids = const []}) async {
    final store = SourceStore(
      starter: [for (final id in ids) source(id)],
      file: file,
    );
    await store.load();
    final controller = SourceTestController(
      store: store,
      tester: SourceTester(
        deviceId: 'dhara-test',
        timeout: const Duration(seconds: 5),
      ),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('nothing is tested to begin with', () async {
    final controller = await open(ids: ['good']);

    expect(controller.isTesting, isFalse);
    expect(controller.statusOf('good'), SourceStatus.untested);
    expect(controller.pingOf('good'), isNull);
    expect(controller.resultOf('good'), isNull);
  });

  test('a run sorts sources into readable, unreadable and unreachable',
      () async {
    final gone = await LocalServer.start();
    final goneUrl = gone.url('/files/');
    await gone.close();
    final controller = await open(ids: ['good', 'site', 'dead']);
    await controller.store.add(
      Source(
        id: 'gone',
        name: 'gone',
        type: SourceType.h5ai,
        category: SourceCategory.mixed,
        baseUrls: [goneUrl],
      ),
    );

    await controller.testAll();

    expect(controller.statusOf('good'), SourceStatus.readable);
    expect(controller.statusOf('site'), SourceStatus.unreadable);
    expect(controller.statusOf('dead'), SourceStatus.unreadable);
    expect(controller.statusOf('gone'), SourceStatus.unreachable);
    expect(controller.pingOf('good'), isNotNull);
    expect(controller.pingOf('gone'), isNull);
    expect(controller.resultOf('good')!.urls.single.sample, ['a.mkv']);
    expect(controller.isTesting, isFalse);
    expect(controller.done, 4);
    expect(controller.total, 4);
  });

  test('shows progress while a run is going', () async {
    final release = Completer<void>();
    server.routes['/slow/'] = (request) async {
      await release.future;
      await request.response.close();
    };
    final controller = await open(ids: ['good', 'slow']);
    final seen = <String>[];
    controller.addListener(
      () => seen.add('${controller.done}/${controller.total}'),
    );

    final run = controller.testAll();
    expect(controller.isTesting, isTrue);
    expect(controller.statusOf('good'), SourceStatus.testing);
    expect(controller.statusOf('slow'), SourceStatus.testing);

    while (controller.done < 1) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(controller.statusOf('good'), SourceStatus.readable);
    expect(controller.statusOf('slow'), SourceStatus.testing);

    release.complete();
    await run;
    expect(seen, containsAllInOrder(['0/2', '1/2', '2/2']));
    expect(controller.isTesting, isFalse);
  });

  test('a second run does not start while one is going', () async {
    final controller = await open(ids: ['good']);

    final first = controller.testAll();
    await controller.testAll();
    await first;

    expect(server.requests, hasLength(1));
  });

  test('results are remembered after a restart', () async {
    final first = await open(ids: ['good', 'dead']);
    await first.testAll();

    final second = await open(ids: ['good', 'dead']);

    expect(second.statusOf('good'), SourceStatus.readable);
    expect(second.statusOf('dead'), SourceStatus.unreadable);
    expect(second.pingOf('good'), isNotNull);
    expect(second.resultOf('good'), isNull, reason: 'details are per session');
    expect(second.store.healthOf('good')!.checkedAt, now);
  });

  test('cancelling keeps what was found and marks nothing else', () async {
    server.routes['/slow/'] = (request) => Completer<void>().future;
    final controller = await open(ids: ['good', 'slow']);

    final run = controller.testAll();
    while (controller.done < 1) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await controller.cancel();
    await run;

    expect(controller.isTesting, isFalse);
    expect(controller.statusOf('good'), SourceStatus.readable);
    expect(controller.statusOf('slow'), SourceStatus.untested);
    expect(controller.store.healthOf('good'), isNotNull);
    expect(controller.store.healthOf('slow'), isNull);

    // And a new run can start afterwards.
    await controller.test([source('good')]);
    expect(controller.done, 1);
  });

  test('"enable all" enables exactly the readable sources', () async {
    final controller = await open(ids: ['good', 'site', 'dead', 'untested']);
    await controller.test([source('good'), source('site'), source('dead')]);

    await controller.enableAllReadable();

    final store = controller.store;
    expect(store.isEnabled('good'), isTrue);
    expect(store.isEnabled('site'), isFalse);
    expect(store.isEnabled('dead'), isFalse);
    expect(store.isEnabled('untested'), isFalse);
  });

  group('the type a test finds', () {
    Source listedAs(String id, SourceType type) => source(id).withType(type);

    test('becomes the type of a server the app could read, and stays after '
        'a restart', () async {
      final store = SourceStore(
        starter: [
          listedAs('good', SourceType.customSite),
          listedAs('site', SourceType.h5ai),
          listedAs('dead', SourceType.customSite),
        ],
        file: file,
      );
      await store.load();
      await store.setEnabled(['good'], enabled: true);
      final controller = SourceTestController(
        store: store,
        tester: SourceTester(deviceId: 'dhara-test'),
        clock: () => now,
      );
      addTearDown(controller.dispose);

      await controller.testAll();

      SourceType typeOf(SourceStore store, String id) =>
          store.sources.singleWhere((source) => source.id == id).type;
      expect(typeOf(store, 'good'), SourceType.directoryListing);
      // The result and what it says of the server stay with the source.
      expect(controller.statusOf('good'), SourceStatus.readable);
      expect(controller.resultOf('good')!.source, store.sources.first);
      expect(store.healthOf('good')!.readable, isTrue);
      expect(store.isEnabled('good'), isTrue);
      // A page the app cannot read says nothing about what the server is.
      expect(typeOf(store, 'site'), SourceType.h5ai);
      expect(typeOf(store, 'dead'), SourceType.customSite);

      final again = SourceStore(
        starter: [listedAs('good', SourceType.customSite)],
        file: file,
      );
      await again.load();
      expect(typeOf(again, 'good'), SourceType.directoryListing);
      expect(again.healthOf('good')!.readable, isTrue);
      expect(again.isEnabled('good'), isTrue);
    });

    test('changes nothing where the list was right', () async {
      final controller = await open(ids: ['good']);
      var changes = 0;
      controller.store.addListener(() => changes++);

      await controller.testAll();

      // Only the test result was recorded.
      expect(changes, 1);
      expect(controller.store.sources.single, source('good'));
    });
  });

  test('editing a source forgets its result; removing it too', () async {
    final controller = await open(ids: ['good', 'site']);
    await controller.testAll();
    var notified = 0;
    controller.addListener(() => notified++);

    await controller.store.update(source('good', path: '/site/'));
    await controller.store.remove('site');

    expect(controller.statusOf('good'), SourceStatus.untested);
    expect(controller.resultOf('good'), isNull);
    expect(controller.statusOf('site'), SourceStatus.untested);
    expect(notified, greaterThanOrEqualTo(2), reason: 'store changes pass on');
  });

  group('the automatic re-test', () {
    test('tests enabled sources that were never tested', () async {
      final controller = await open(ids: ['good', 'site']);
      await controller.store.setEnabled(['good'], enabled: true);

      await controller.retestEnabledIfStale();

      expect(server.requests.map((r) => r.uri.path), ['/good/']);
      expect(controller.statusOf('good'), SourceStatus.readable);
      expect(controller.statusOf('site'), SourceStatus.untested);
    });

    test('leaves fresh results alone and redoes old ones', () async {
      final controller = await open(ids: ['good']);
      await controller.store.setEnabled(['good'], enabled: true);
      await controller.testAll();
      expect(server.requests, hasLength(1));

      now = now.add(const Duration(days: 6));
      await controller.retestEnabledIfStale();
      expect(server.requests, hasLength(1));

      now = now.add(const Duration(days: 2));
      await controller.retestEnabledIfStale();
      expect(server.requests, hasLength(2));
      expect(controller.store.healthOf('good')!.checkedAt, now);
    });

    test('notices a server that died', () async {
      final controller = await open(ids: ['good']);
      await controller.store.setEnabled(['good'], enabled: true);
      await controller.testAll();
      server.routes.remove('/good/');
      now = now.add(const Duration(days: 8));

      await controller.retestEnabledIfStale();

      expect(controller.statusOf('good'), SourceStatus.unreadable);
      expect(controller.store.isEnabled('good'), isTrue, reason: 'only marked');
    });

    test('does nothing when nothing is enabled', () async {
      final controller = await open(ids: ['good']);

      await controller.retestEnabledIfStale();

      expect(server.requests, isEmpty);
      expect(controller.isTesting, isFalse);
    });
  });
}
