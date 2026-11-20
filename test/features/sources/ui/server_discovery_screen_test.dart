import 'dart:io';

import 'package:dhara/app.dart';
import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/browse/browse_controller.dart';
import 'package:dhara/features/history/history_controller.dart';
import 'package:dhara/features/home/home_controller.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/anime_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/review_controller.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/my_list/my_list_controller.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_list.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/features/sources/source_tester.dart';
import 'package:dhara/features/sources/ui/server_discovery_screen.dart';
import 'package:dhara/features/sources/ui/source_form_dialog.dart';
import 'package:dhara/features/sources/ui/source_list_files.dart';
import 'package:dhara/theme/theme.dart';
import 'package:dhara/widgets/chips.dart';
import 'package:dhara/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/local_server.dart';

Source _source(
  String id, {
  String? name,
  SourceType type = SourceType.h5ai,
  List<String>? urls,
  String? isp,
}) => Source(
  id: id,
  name: name ?? 'Server $id',
  isp: isp,
  type: type,
  category: SourceCategory.movies,
  baseUrls: [
    for (final url in urls ?? ['http://10.0.0.1/$id/']) Uri.parse(url),
  ],
);

SourceHealth _health({bool reachable = true, bool readable = true, int? ms}) =>
    SourceHealth(
      checkedAt: DateTime(2026, 11, 12, 21, 30),
      reachable: reachable,
      readable: readable,
      ping: ms == null ? null : Duration(milliseconds: ms),
    );

/// Stands in for the system file dialogs.
class _FakeFiles extends SourceListFiles {
  _FakeFiles({this.toRead, this.readError});

  final String? toRead;
  final SourceFormatException? readError;
  String? saved;

  @override
  Future<String?> pickAndRead() async {
    final error = readError;
    if (error != null) throw error;
    return toRead;
  }

  @override
  Future<String?> save(String json) async {
    saved = json;
    return r'C:\Users\me\dhara-sources.json';
  }
}

void main() {
  /// Shows the screen over a store holding [sources]. The store has no
  /// file: real file I/O does not mix with a widget test's fake clock.
  Future<SourceTestController> show(
    WidgetTester tester, {
    required List<Source> sources,
    Set<String> enabled = const {},
    Map<String, SourceHealth> health = const {},
    SourceListFiles files = const SourceListFiles(),
    Size size = const Size(1600, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = SourceStore(starter: sources);
    await store.setEnabled(enabled, enabled: true);
    await store.recordHealth(health);
    final controller = SourceTestController(
      store: store,
      tester: SourceTester(deviceId: 'dhara-test'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      SourcesScope(
        controller: controller,
        child: MaterialApp(
          theme: buildDharaTheme(),
          // What the screen has to say is shown by the app's message host.
          builder: (context, child) => ToastHost(child: child!),
          home: ServerDiscoveryScreen(files: files),
        ),
      ),
    );
    return controller;
  }

  Future<void> chooseFromMenu(
    WidgetTester tester,
    String id,
    String item,
  ) async {
    await tester.tap(find.byKey(Key('menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every source with its details', (tester) async {
    await show(
      tester,
      sources: [
        _source('alpha', name: 'DhakaFlix 7', isp: 'SAM Online'),
        _source(
          'beta',
          name: 'ICC FTP 3',
          type: SourceType.directoryListing,
          urls: ['http://10.16.100.241/a/', 'http://10.16.100.241/b/'],
        ),
        _source('gamma', type: SourceType.customSite),
      ],
    );

    expect(find.text('Server Discovery'), findsOneWidget);
    expect(find.text('DhakaFlix 7'), findsOneWidget);
    expect(find.text('http://10.0.0.1/alpha/'), findsOneWidget);
    expect(find.text('SAM Online'), findsOneWidget);
    expect(find.text('http://10.16.100.241/a/  +1 more'), findsOneWidget);
    expect(find.text('h5ai'), findsOneWidget);
    expect(find.text('Folder listing'), findsOneWidget);
    expect(find.text('Website'), findsOneWidget);
    expect(find.text('Not tested'), findsNWidgets(3));
    expect(find.text('3 server types'), findsOneWidget);
    expect(find.text('no server reachable'), findsOneWidget);
  });

  testWidgets('shows what the last saved test found', (tester) async {
    await show(
      tester,
      sources: [
        _source('fast'),
        _source('slow'),
        _source('dead'),
        _source('site', type: SourceType.customSite),
        _source('broken'),
        _source('new'),
      ],
      enabled: {'fast'},
      health: {
        'fast': _health(ms: 14),
        'slow': _health(ms: 350),
        'dead': _health(reachable: false, readable: false),
        'site': _health(readable: false, ms: 90),
        'broken': _health(readable: false, ms: 20),
      },
    );

    expect(find.text('Reachable'), findsNWidgets(3), reason: '2 rows + stat');
    expect(find.text('Unreachable'), findsNWidgets(2), reason: 'row + filter');
    expect(find.text('No adapter'), findsOneWidget);
    expect(find.text('Problem'), findsOneWidget);
    expect(find.text('Not tested'), findsOneWidget);
    expect(find.text('14 ms'), findsNWidgets(2), reason: 'row + fastest');
    expect(find.text('350 ms'), findsOneWidget);
    expect(find.text('Checked 12 Nov, 21:30'), findsNWidgets(5));
    expect(find.text('2 the app can read'), findsOneWidget);
    expect(find.text('Server fast'), findsNWidgets(2), reason: 'row + fastest');
  });

  testWidgets('filters the list', (tester) async {
    await show(
      tester,
      sources: [_source('up'), _source('down'), _source('new')],
      enabled: {'new'},
      health: {
        'up': _health(ms: 10),
        'down': _health(reachable: false, readable: false),
      },
    );

    await tester.tap(find.byKey(const Key('filter-reachable')));
    await tester.pump();
    expect(find.text('http://10.0.0.1/up/'), findsOneWidget);
    expect(find.text('http://10.0.0.1/down/'), findsNothing);
    expect(find.text('http://10.0.0.1/new/'), findsNothing);

    await tester.tap(find.byKey(const Key('filter-unreachable')));
    await tester.pump();
    expect(find.text('http://10.0.0.1/down/'), findsOneWidget);
    expect(find.text('http://10.0.0.1/up/'), findsNothing);

    await tester.tap(find.byKey(const Key('filter-untested')));
    await tester.pump();
    expect(find.text('http://10.0.0.1/new/'), findsOneWidget);
    expect(find.text('http://10.0.0.1/up/'), findsNothing);
    expect(find.text('http://10.0.0.1/down/'), findsNothing);

    await tester.tap(find.byKey(const Key('filter-readable')));
    await tester.pump();
    expect(find.text('http://10.0.0.1/up/'), findsOneWidget);
    expect(find.text('http://10.0.0.1/new/'), findsNothing);
    expect(find.text('http://10.0.0.1/down/'), findsNothing);

    await tester.tap(find.byKey(const Key('filter-enabled')));
    await tester.pump();
    expect(find.text('http://10.0.0.1/new/'), findsOneWidget);
    expect(find.text('http://10.0.0.1/up/'), findsNothing);

    await tester.tap(find.byKey(const Key('filter-all')));
    await tester.pump();
    expect(find.text('http://10.0.0.1/up/'), findsOneWidget);
    expect(find.text('http://10.0.0.1/down/'), findsOneWidget);
  });

  testWidgets('the search field narrows the list by name, ISP or address, '
      'together with the filter', (tester) async {
    final field = find.byKey(const Key('discovery-search'));
    Source named(String id, String name, {String? isp}) => Source(
      id: id,
      name: name,
      isp: isp,
      type: SourceType.h5ai,
      category: SourceCategory.mixed,
      baseUrls: [Uri.parse('http://10.0.0.1/$id/')],
    );
    await show(
      tester,
      sources: [
        named('one', 'CircleFTP ftp4', isp: 'Circle Network'),
        named('two', 'CircleFTP ftp5', isp: 'Circle Network'),
        named('three', 'ICC ftps3', isp: 'ICC Communication'),
      ],
      enabled: {'two'},
    );
    List<String> shown() => [
      for (final id in ['one', 'two', 'three'])
        if (find.text('http://10.0.0.1/$id/').evaluate().isNotEmpty) id,
    ];
    Future<void> type(String text) async {
      await tester.enterText(
        find.descendant(of: field, matching: find.byType(TextField)),
        text,
      );
      await tester.pump();
    }

    expect(shown(), ['one', 'two', 'three']);

    await type('circle');
    expect(shown(), ['one', 'two']);

    // Every word must be there, in any order and any case.
    await type('FTP5  circle');
    expect(shown(), ['two']);

    await type('icc communication');
    expect(shown(), ['three']);

    await type('10.0.0.1/one');
    expect(shown(), ['one']);

    await type('circle');
    await tester.tap(find.byKey(const Key('filter-enabled')));
    await tester.pump();
    expect(shown(), ['two']);

    await type('nothing like it');
    expect(shown(), isEmpty);
    expect(find.text('No servers in this view'), findsOneWidget);

    await type('');
    await tester.tap(find.byKey(const Key('filter-all')));
    await tester.pump();
    expect(shown(), ['one', 'two', 'three']);
  });

  testWidgets('an empty view says so', (tester) async {
    await show(tester, sources: [_source('new')]);

    await tester.tap(find.byKey(const Key('filter-enabled')));
    await tester.pump();

    expect(find.text('No servers in this view'), findsOneWidget);
  });

  testWidgets('the switch turns a source on and off', (tester) async {
    final controller = await show(tester, sources: [_source('alpha')]);

    await tester.tap(find.byKey(const Key('enable-alpha')));
    await tester.pumpAndSettle();
    expect(controller.store.isEnabled('alpha'), isTrue);
    expect(tester.widget<DharaSwitch>(find.byType(DharaSwitch)).value, isTrue);

    await tester.tap(find.byKey(const Key('enable-alpha')));
    await tester.pumpAndSettle();
    expect(controller.store.isEnabled('alpha'), isFalse);
  });

  testWidgets('says so when a website is switched on that it cannot read', (
    tester,
  ) async {
    final controller = await show(
      tester,
      sources: [
        _source('alpha'),
        _source('portal', name: 'Portal', type: SourceType.customSite),
      ],
    );
    String said() => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('toast')),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.textSpan?.toPlainText() ?? text.data ?? '')
        .join();

    // A server it can read is switched on without a word.
    await tester.tap(find.byKey(const Key('enable-alpha')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(said(), isEmpty);

    await tester.tap(find.byKey(const Key('enable-portal')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.store.isEnabled('portal'), isTrue);
    expect(said(), contains('Portal is a website'));

    // Let the message leave before the test ends.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('"Enable all reachable" enables what the app can read', (
    tester,
  ) async {
    final controller = await show(
      tester,
      sources: [
        _source('up'),
        _source('site'),
        _source('down'),
        _source('new'),
      ],
      health: {
        'up': _health(ms: 10),
        'site': _health(readable: false),
        'down': _health(reachable: false, readable: false),
      },
    );

    await tester.tap(find.byKey(const Key('enable-all')));
    await tester.pumpAndSettle();

    final store = controller.store;
    expect(store.isEnabled('up'), isTrue);
    expect(store.isEnabled('site'), isFalse);
    expect(store.isEnabled('down'), isFalse);
    expect(store.isEnabled('new'), isFalse);
    expect(find.text('Enabled 1 more server.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('enable-all')));
    await tester.pumpAndSettle();
    expect(find.textContaining('No more reachable servers'), findsOneWidget);
  });

  testWidgets('"Test all" runs the tester and shows each outcome', (
    tester,
  ) async {
    // Widget tests answer every HTTP request with status 400, so each
    // server counts as "answered, but with an error".
    final controller = await show(
      tester,
      sources: [_source('alpha'), _source('beta')],
    );

    await tester.tap(find.byKey(const Key('test-all')));
    await tester.pump();
    for (var i = 0; i < 20 && controller.isTesting; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();

    expect(controller.isTesting, isFalse);
    expect(find.text('Problem'), findsNWidgets(2));
    expect(find.text('The server answered 400.'), findsNWidgets(2));
    expect(find.text('Test all'), findsOneWidget);
    expect(controller.store.healthOf('alpha')!.reachable, isTrue);
  });

  testWidgets('shows what a real run found on each server', (tester) async {
    // Real HTTP against a local server instead of the canned 400 answers.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    late LocalServer server;
    await tester.runAsync(() async => server = await LocalServer.start());
    addTearDown(() => server.close());
    server
      ..serve('/DHAKA-FLIX-7/', fixture('listings/h5ai_root.html'))
      ..serve('/site/', fixture('listings/not_a_listing.html'));

    final controller = await show(
      tester,
      sources: [
        // The list calls it a folder listing; the test finds h5ai.
        _source(
          'flix',
          type: SourceType.directoryListing,
          urls: ['${server.url('/DHAKA-FLIX-7/')}'],
        ),
        _source(
          'site',
          type: SourceType.customSite,
          urls: ['${server.url('/site/')}'],
        ),
        _source('gone', urls: ['${server.url('/gone/')}']),
      ],
    );
    await tester.runAsync(controller.testAll);
    await tester.pump();

    expect(
      find.text(
        '4 items · 3D Movies · English Movies · '
        'Foreign Language Movies · Kolkata Bangla Movies',
      ),
      findsOneWidget,
    );
    expect(find.text('h5ai'), findsNWidgets(2), reason: 'detected, not listed');
    expect(find.text('Folder listing'), findsNothing);
    expect(find.text('Website: Example Net - Home'), findsOneWidget);
    expect(find.text('No adapter'), findsOneWidget);
    expect(find.text('The server answered 404.'), findsOneWidget);
    expect(find.text('Problem'), findsOneWidget);
    expect(find.text('1 the app can read'), findsOneWidget);
  });

  testWidgets('a website that is a page of links says so, lists them, and '
      'adds one as a source', (tester) async {
    // Real HTTP against a local server instead of the canned 400 answers.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    late LocalServer server;
    await tester.runAsync(() async => server = await LocalServer.start());
    addTearDown(() => server.close());
    // The front page of FTPmedia, as it really is.
    server.serve('/', fixture('listings/ftpmedia_portal.html'));
    final portal = Source(
      id: 'ftpmedia',
      name: 'FTPmedia',
      provider: 'FTPmedia',
      type: SourceType.customSite,
      category: SourceCategory.mixed,
      baseUrls: [server.url('/')],
    );
    final flix = Source(
      id: 'dhakaflix-7',
      name: 'DhakaFlix 7',
      type: SourceType.h5ai,
      category: SourceCategory.movies,
      baseUrls: [Uri.parse('http://172.16.50.7/DHAKA-FLIX-7/')],
      portalUrl: Uri.parse('http://172.16.50.4/'),
    );

    final controller = await show(tester, sources: [portal, flix]);
    // Before a test nothing is known of its links.
    await tester.tap(find.byKey(const Key('menu-ftpmedia')));
    await tester.pumpAndSettle();
    expect(find.text('Linked servers'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // Only the front page itself is tested.
    await tester.runAsync(() => controller.test([portal]));
    await tester.pump();
    expect(
      find.textContaining('Links to 6 other servers · Website: FTPmedia.net'),
      findsOneWidget,
    );

    await chooseFromMenu(tester, 'ftpmedia', 'Linked servers');
    expect(find.text('Servers FTPmedia links to'), findsOneWidget);
    expect(find.text('Media Live Movies'), findsOneWidget);
    expect(find.text('http://10.50.50.51/'), findsOneWidget);
    // The one that is DhakaFlix's front page is known, and not offered.
    expect(find.text('In your list: DhakaFlix 7'), findsOneWidget);
    expect(find.byKey(const Key('linked-add-172.16.50.4')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('linked-add-10.50.50.51')));
    await tester.tap(find.byKey(const Key('linked-add-10.50.50.51')));
    await tester.pumpAndSettle();
    // The form any new source goes through, filled in to be looked over.
    // (The page's own button is called the same.)
    expect(find.text('Add source'), findsNWidgets(2));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('source-name')))
          .controller!
          .text,
      'FTPmedia: Media Live Movies',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('source-urls')))
          .controller!
          .text,
      'http://10.50.50.51/',
    );
    await tester.tap(find.byKey(const Key('source-save')));
    await tester.pumpAndSettle();

    final added = controller.store.sources.last;
    expect(added.id, 'ftpmedia-media-live-movies');
    expect(added.baseUrls.single, Uri.parse('http://10.50.50.51/'));
    expect(added.provider, 'FTPmedia');
    expect(added.portalUrl, server.url('/'));
    expect(added.notes, 'Linked from FTPmedia.');
    // In the list, but neither tested nor switched on.
    expect(controller.store.isEnabled(added.id), isFalse);
    expect(controller.resultOf(added.id), isNull);
    expect(find.textContaining('is in the list'), findsOneWidget);
    expect(server.requests.map((request) => request.headers.host).toSet(), {
      '127.0.0.1',
    });
  });

  group('adding and editing', () {
    testWidgets('a new source goes through the form into the list', (
      tester,
    ) async {
      final controller = await show(tester, sources: [_source('my-server')]);

      await tester.tap(find.byKey(const Key('add-source')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('source-name')), 'My Server');
      await tester.enterText(
        find.byKey(const Key('source-urls')),
        'http://10.0.0.9/movies\nhttp://10.0.0.9/series/',
      );
      await tester.tap(find.byKey(const Key('source-save')));
      await tester.pumpAndSettle();

      final added = controller.store.sources.last;
      expect(added.id, 'my-server-2', reason: 'the plain id was taken');
      expect(added.name, 'My Server');
      expect(added.baseUrls.map((url) => '$url'), [
        'http://10.0.0.9/movies/',
        'http://10.0.0.9/series/',
      ]);
      expect(controller.store.isEnabled(added.id), isFalse);
      expect(find.text('My Server'), findsOneWidget);
    });

    testWidgets('the form says what is wrong and stays open', (tester) async {
      final controller = await show(tester, sources: const []);

      await tester.tap(find.byKey(const Key('add-source')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('source-name')), 'Mine');
      await tester.enterText(
        find.byKey(const Key('source-urls')),
        'http://10.0.0.9/ok/\nftp://10.0.0.9/movies/',
      );
      await tester.tap(find.byKey(const Key('source-save')));
      await tester.pumpAndSettle();

      expect(
        find.text('Base URL on line 2: must be an http or https URL.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('source-save')), findsOneWidget);
      expect(controller.store.sources, isEmpty);

      await tester.enterText(
        find.byKey(const Key('source-urls')),
        'http://me:secret@10.0.0.9/movies/',
      );
      await tester.tap(find.byKey(const Key('source-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('user name or password'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('source-name')), '');
      await tester.enterText(
        find.byKey(const Key('source-urls')),
        'http://10.0.0.9/',
      );
      await tester.tap(find.byKey(const Key('source-save')));
      await tester.pumpAndSettle();
      expect(find.text('Name: is missing.'), findsOneWidget);
    });

    testWidgets('editing keeps the id and replaces the details', (
      tester,
    ) async {
      final controller = await show(
        tester,
        sources: [_source('alpha')],
        enabled: {'alpha'},
      );

      await chooseFromMenu(tester, 'alpha', 'Edit');
      expect(find.text('Edit source'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('source-name')), 'Renamed');
      await tester.tap(find.byKey(const Key('source-save')));
      await tester.pumpAndSettle();

      final edited = controller.store.sources.single;
      expect(edited.id, 'alpha');
      expect(edited.name, 'Renamed');
      expect(edited.type, SourceType.h5ai);
      expect(controller.store.isEnabled('alpha'), isTrue);
    });

    testWidgets('cancelling the form changes nothing', (tester) async {
      final controller = await show(tester, sources: [_source('alpha')]);

      await chooseFromMenu(tester, 'alpha', 'Edit');
      await tester.enterText(find.byKey(const Key('source-name')), 'Renamed');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(controller.store.sources.single.name, 'Server alpha');
    });
  });

  testWidgets('a source is removed only after confirming', (tester) async {
    final controller = await show(
      tester,
      sources: [_source('alpha'), _source('beta')],
    );

    await chooseFromMenu(tester, 'alpha', 'Remove');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.store.sources, hasLength(2));

    await chooseFromMenu(tester, 'alpha', 'Remove');
    await tester.tap(find.byKey(const Key('confirm-remove')));
    await tester.pumpAndSettle();

    expect(controller.store.sources.map((s) => s.id), ['beta']);
    expect(find.text('Server alpha'), findsNothing);
  });

  group('import and export', () {
    String listOf(List<Source> sources) =>
        SourceStore(starter: sources).exportJson();

    testWidgets('an import shows what will change, then applies it', (
      tester,
    ) async {
      final files = _FakeFiles(
        toRead: listOf([
          _source('alpha'),
          _source('beta', name: 'Beta, renamed'),
          _source('one'),
          _source('two'),
        ]),
      );
      final controller = await show(
        tester,
        sources: [_source('alpha'), _source('beta')],
        files: files,
      );

      await tester.tap(find.byKey(const Key('import-sources')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('2 new and 1 changed (1 already in your list)'),
        findsOneWidget,
      );
      expect(controller.store.sources, hasLength(2), reason: 'not yet');

      await tester.tap(find.byKey(const Key('confirm-import')));
      await tester.pumpAndSettle();

      expect(controller.store.sources.map((s) => s.id), [
        'alpha',
        'beta',
        'one',
        'two',
      ]);
      expect(controller.store.sources[1].name, 'Beta, renamed');
      expect(find.text('Imported: 2 added, 1 replaced.'), findsOneWidget);
    });

    testWidgets('a cancelled import changes nothing', (tester) async {
      final controller = await show(
        tester,
        sources: [_source('alpha')],
        files: _FakeFiles(toRead: listOf([_source('one')])),
      );

      await tester.tap(find.byKey(const Key('import-sources')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(controller.store.sources, hasLength(1));
    });

    testWidgets('a broken file is refused with the reason', (tester) async {
      final controller = await show(
        tester,
        sources: [_source('alpha')],
        files: _FakeFiles(
          toRead: '{"schemaVersion": 1, "sources": [{"id": "x"}]}',
        ),
      );

      await tester.tap(find.byKey(const Key('import-sources')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Nothing was imported. sources[0]'),
        findsOneWidget,
      );
      expect(controller.store.sources, hasLength(1));
    });

    testWidgets('a file that is too large or unreadable is refused', (
      tester,
    ) async {
      await show(
        tester,
        sources: const [],
        files: _FakeFiles(
          readError: const SourceFormatException('The file is too large.'),
        ),
      );

      await tester.tap(find.byKey(const Key('import-sources')));
      await tester.pumpAndSettle();

      expect(
        find.text('Nothing was imported. The file is too large.'),
        findsOneWidget,
      );
    });

    testWidgets('a file with nothing new says so', (tester) async {
      await show(
        tester,
        sources: [_source('alpha')],
        files: _FakeFiles(toRead: listOf([_source('alpha')])),
      );

      await tester.tap(find.byKey(const Key('import-sources')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing new'), findsOneWidget);
    });

    testWidgets('picking no file does nothing', (tester) async {
      await show(tester, sources: [_source('alpha')], files: _FakeFiles());

      await tester.tap(find.byKey(const Key('import-sources')));
      await tester.pumpAndSettle();

      // Nothing was said either.
      expect(
        find.descendant(
          of: find.byKey(const Key('toast')),
          matching: find.text(''),
        ),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('an export writes the whole list as a source list', (
      tester,
    ) async {
      final files = _FakeFiles();
      final controller = await show(
        tester,
        sources: [_source('alpha'), _source('beta')],
        enabled: {'alpha'},
        files: files,
      );

      await tester.tap(find.byKey(const Key('export-sources')));
      await tester.pumpAndSettle();

      expect(parseSourceList(files.saved!), controller.store.sources);
      expect(files.saved, isNot(contains('enabled')));
      expect(find.text('Saved 2 sources.'), findsOneWidget);
    });
  });

  testWidgets('fits a small window without overflowing', (tester) async {
    await show(
      tester,
      size: const Size(1040, 600),
      sources: [
        _source(
          'long',
          name: 'A server with a very long name that will not fit the column',
          isp: 'An ISP with a long name too',
          urls: ['http://a-very-long-host-name.example.net/with/a/long/path/'],
        ),
        _source('up'),
      ],
      health: {'up': _health(ms: 14), 'long': _health(readable: false, ms: 9)},
    );

    // Any overflow would already have failed the test; the narrow layout
    // drops the ISP column.
    expect(find.text('An ISP with a long name too'), findsNothing);
    expect(find.text('ISP'), findsNothing);
  });

  testWidgets('opens from the rail and goes back to Home', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryKeyValueStore();
    final controller = SourceTestController(
      store: SourceStore(starter: [_source('alpha')]),
      tester: SourceTester(deviceId: 'dhara-test'),
    );
    addTearDown(controller.dispose);
    final library = LocalLibrary(LibraryDb.inMemory());
    final index = IndexController(
      library: library,
      sources: controller.store,
      deviceId: 'dhara-test',
    );
    final titles = TitlesController(library: library, index: index);
    final tmdbKey = TmdbKeyController(MemorySecretStore());
    final match = MatchController(
      library: library,
      titles: titles,
      tmdbKey: tmdbKey,
    );
    await tester.pumpWidget(
      DharaApp(
        settings: SettingsController(store),
        resumeStore: ResumeStore(),
        sourceTests: controller,
        index: index,
        titles: titles,
        tmdbKey: tmdbKey,
        match: match,
        review: ReviewController(
          library: library,
          titles: titles,
          match: match,
          tmdbKey: tmdbKey,
        ),
        anime: AnimeController(library: library),
        home: HomeController(library: library, titles: titles, match: match),
        myList: MyListController(library: library),
        browse: BrowseController(library: library, titles: titles),
        history: HistoryController(
          library: library,
          titles: titles,
          resume: ResumeStore(),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('rail-discovery')));
    await tester.pumpAndSettle();
    expect(find.text('Server Discovery'), findsOneWidget);
    expect(find.text('Server alpha'), findsOneWidget);

    // The page has no Back of its own: the title bar's leads back.
    await tester.tap(find.byKey(const Key('shell-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home')), findsOneWidget);
  });

  group('uniqueSourceId', () {
    test('makes an id from the name', () {
      expect(uniqueSourceId('My Server!', {}), 'my-server');
      expect(
        uniqueSourceId('  DhakaFlix   7 (Movies) ', {}),
        'dhakaflix-7-movies',
      );
      expect(uniqueSourceId('ICC_FTP#3', {}), 'icc-ftp-3');
    });

    test('falls back when the name has nothing usable', () {
      expect(uniqueSourceId('', {}), 'source');
      expect(uniqueSourceId('বাংলা সার্ভার', {}), 'source');
    });

    test('numbers an id that is taken', () {
      expect(uniqueSourceId('Mine', {'mine'}), 'mine-2');
      expect(uniqueSourceId('Mine', {'mine', 'mine-2', 'mine-3'}), 'mine-4');
    });

    test('keeps long names within the id length limit', () {
      final id = uniqueSourceId('word ' * 40, {});

      expect(id.length, lessThanOrEqualTo(48));
      expect(id, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')));
    });
  });
}
