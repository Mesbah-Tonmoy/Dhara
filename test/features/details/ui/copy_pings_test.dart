// The copies list with live pings, against a web server on this machine.
import 'dart:io';

import 'package:dhara/features/details/ui/copies_table.dart';
import 'package:dhara/features/details/ui/copy_pings.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/playback/copy_choice.dart';
import 'package:dhara/features/playback/copy_probe.dart';
import 'package:dhara/features/playback/media_sessions.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_emby.dart';
import '../../../support/local_server.dart';

Source _source(String id) => Source(
  id: id,
  name: 'Server $id',
  type: SourceType.h5ai,
  category: SourceCategory.movies,
  baseUrls: [Uri.parse('http://127.0.0.1/$id/')],
);

void main() {
  late LocalServer server;
  late SourceStore sources;
  LivePings? last;

  TitleCopy copy(int id, String source, String path, {int? height}) =>
      TitleCopy(
        fileId: id,
        sourceId: source,
        name: path.substring(1),
        path: path,
        url: server.url(path),
        height: height,
      );

  void video(String path, {Duration delay = Duration.zero}) {
    server.routes[path] = (request) async {
      await Future<void>.delayed(delay);
      request.response.statusCode = HttpStatus.partialContent;
      try {
        request.response.add(List.filled(1024, 0));
        await request.response.close();
      } on Object {
        // The client hung up.
      }
    };
  }

  Future<void> pump(
    WidgetTester tester,
    List<TitleCopy> copies, {
    bool withProber = true,
    MediaSessions? sessions,
  }) async {
    tester.view
      ..physicalSize = const Size(1280, 720)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CopyProbeScope(
              make: withProber
                  ? () => CopyProber(
                      isAllowedHost: (host) => host == '127.0.0.1',
                      timeout: const Duration(seconds: 2),
                    )
                  : null,
              child: MediaSessionsScope(
                sessions: sessions,
                child: CopyPings(
                  copies: copies,
                  sources: sources,
                  builder: (context, live) {
                    last = live;
                    return SingleChildScrollView(
                      child: CopiesTable(
                        copies: rankCopies(
                          copies,
                          sources,
                          pings: live.done ? live.byFile : const {},
                        ),
                        sources: sources,
                        pings: live.byFile,
                        onPlay: (_) {},
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Lets the real requests run until [done].
  Future<void> until(WidgetTester tester, bool Function() done) async {
    final watch = Stopwatch()..start();
    while (!done() && watch.elapsed < const Duration(seconds: 10)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'waited 10 s');
  }

  List<String> listed(WidgetTester tester) => [
    for (final copy
        in tester.widget<CopiesTable>(find.byType(CopiesTable)).copies)
      copy.name,
  ];

  setUp(() async {
    // Widget tests answer every request with a made-up 400 otherwise.
    HttpOverrides.global = null;
    last = null;
    server = await LocalServer.start();
    sources = SourceStore(starter: [_source('a'), _source('b'), _source('c')]);
    await sources.setEnabled(['a', 'b', 'c'], enabled: true);
  });

  tearDown(() => server.close());

  testWidgets('asks the servers as the list comes up, and lists the copy '
      'that answers fastest first', (tester) async {
    video('/slow.mkv', delay: const Duration(milliseconds: 300));
    video('/fast.mkv', delay: const Duration(milliseconds: 20));
    final copies = [
      copy(1, 'a', '/slow.mkv', height: 1080),
      copy(2, 'b', '/fast.mkv', height: 1080),
      copy(3, 'c', '/gone.mkv', height: 1080),
    ];

    await pump(tester, copies);
    expect(last!.pinging, isTrue);
    // Never tested, and no answer yet.
    expect(find.text('Not tested'), findsNWidgets(3));

    await until(tester, () => last!.done);

    expect(last!.byFile.keys, unorderedEquals([1, 2, 3]));
    expect(last!.byFile[2]!.time, lessThan(last!.byFile[1]!.time!));
    expect(listed(tester), ['fast.mkv', 'slow.mkv', 'gone.mkv']);
    expect(find.text('Not tested'), findsNothing);
    expect(find.text('No answer'), findsOneWidget);
    expect(find.textContaining(' ms'), findsNWidgets(2));
    // The one that answers fastest is the one Play takes.
    expect(find.text('BEST'), findsOneWidget);
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.text('No answer'),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      contains('not on the server'),
    );
    expect(
      server.requests.map((request) => request.headers.value('range')),
      everyElement('bytes=0-0'),
    );
  });

  testWidgets('asks again when told to', (tester) async {
    video('/film.mkv');
    await pump(tester, [copy(1, 'a', '/film.mkv')]);
    await until(tester, () => last!.done);
    expect(server.requests, hasLength(1));

    await tester.runAsync(() async => last!.ping!());
    await tester.pump();
    expect(last!.pinging, isTrue);
    await until(tester, () => last!.done);

    expect(server.requests, hasLength(2));
  });

  testWidgets('a long list is only asked on demand', (tester) async {
    final copies = [
      for (var i = 0; i < CopyPings.autoLimit + 1; i++)
        copy(i + 1, 'a', '/part$i.mkv'),
    ];
    for (final each in copies) {
      video(each.path);
    }

    await pump(tester, copies);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(server.requests, isEmpty);
    expect(last!.pinging, isFalse);

    await tester.runAsync(() async => last!.ping!());
    await until(tester, () => last!.done);
    expect(server.requests, hasLength(copies.length));
  });

  testWidgets('without a prober nothing is asked, and the last test counts', (
    tester,
  ) async {
    video('/film.mkv');
    await pump(tester, [copy(1, 'a', '/film.mkv')], withProber: false);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(last!.ping, isNull);
    expect(last!.byFile, isEmpty);
    expect(server.requests, isEmpty);
    expect(find.text('Not tested'), findsOneWidget);
  });

  testWidgets('a copy that cannot be played is not asked', (tester) async {
    video('/film.mkv');
    final withPassword = TitleCopy(
      fileId: 1,
      sourceId: 'a',
      name: 'film.mkv',
      path: '/film.mkv',
      url: server.url('/film.mkv').replace(userInfo: 'user:pw'),
    );

    await pump(tester, [withPassword]);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(last!.ping, isNull);
    expect(server.requests, isEmpty);
  });

  testWidgets('a file of a media server is asked for with its session', (
    tester,
  ) async {
    final emby = FakeEmby(server);
    final media = Source(
      id: 'e',
      name: 'Emby',
      type: SourceType.emby,
      category: SourceCategory.movies,
      baseUrls: [server.url('/')],
    );
    sources = SourceStore(starter: [media]);
    await sources.setEnabled(['e'], enabled: true);
    final sessions = MediaSessions(deviceId: 'dhara-test', sources: sources);
    addTearDown(sessions.close);
    final film = copy(1, 'e', '/Videos/101/stream.mkv');

    // Without a session the server refuses the file.
    await pump(tester, [film]);
    await until(tester, () => last!.done);
    expect(last!.byFile[1]!.ok, isFalse);
    expect(find.text('No answer'), findsOneWidget);
    expect(emby.signIns, isEmpty);

    // With one (the app signs in as the guest) it is there.
    await tester.pumpWidget(const SizedBox());
    await pump(tester, [film], sessions: sessions);
    await until(tester, () => last!.done);
    expect(last!.byFile[1]!.ok, isTrue);
    expect(find.textContaining(' ms'), findsOneWidget);
    expect(emby.signIns, hasLength(1));

    // The server stops taking that session: the copy is refused once,
    // and the next ping signs in afresh.
    emby.token = 'token-2';
    await tester.runAsync(() async => last!.ping!());
    await tester.pump();
    await until(tester, () => last!.done);
    expect(last!.byFile[1]!.ok, isFalse);
    await tester.runAsync(() async => last!.ping!());
    await tester.pump();
    await until(tester, () => last!.done);
    expect(last!.byFile[1]!.ok, isTrue);
    expect(emby.signIns, hasLength(2));
  });
}
