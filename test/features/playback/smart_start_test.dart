// "127.0.0.1" and "localhost" reach the same local server but count as two
// hosts, which is what the redirect rule is about.
import 'dart:io';

import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/release_name.dart';
import 'package:dhara/features/playback/copy_probe.dart';
import 'package:dhara/features/playback/play.dart';
import 'package:dhara/features/playback/smart_start.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_server.dart';

Uri _at(String name) => Uri.parse('http://10.0.0.1/$name.mkv');

PlayCandidate _copy(String name, [int? height]) =>
    PlayCandidate(_at(name), height: height);

CopyProbe _answer(String name, int ms) => CopyProbe(
  url: _at(name),
  time: Duration(milliseconds: ms),
  address: _at(name),
);

CopyProbe _silent(String name) =>
    CopyProbe(url: _at(name), problem: 'The server did not answer in time.');

void main() {
  group('CopyPick', () {
    test('of one quality, the first to answer is taken at once', () {
      final pick = CopyPick([
        _copy('a', 1080),
        _copy('b', 1080),
        _copy('c', 1080),
      ], preferred: PreferredQuality.best);

      // "b" answers first: the others can only be slower.
      expect(pick.add(_answer('b', 12))?.url, _at('b'));
    });

    test('a copy that would be preferred is waited for', () {
      final pick = CopyPick([
        _copy('uhd', 2160),
        _copy('hd', 720),
      ], preferred: PreferredQuality.best);

      expect(pick.add(_answer('hd', 5)), isNull);
      expect(pick.add(_answer('uhd', 80))?.url, _at('uhd'));
    });

    test('if the preferred copy does not answer, the next best is taken', () {
      final pick = CopyPick([
        _copy('uhd', 2160),
        _copy('fullHd', 1080),
        _copy('hd', 720),
      ], preferred: PreferredQuality.best);

      expect(pick.add(_answer('hd', 5)), isNull);
      expect(pick.add(_silent('uhd')), isNull, reason: '1080p may yet answer');
      expect(pick.add(_answer('fullHd', 90))?.url, _at('fullHd'));
    });

    test('a named quality is taken before a sharper one that is faster', () {
      final pick = CopyPick([
        _copy('uhd', 2160),
        _copy('fullHd', 1080),
      ], preferred: PreferredQuality.fullHd);

      expect(pick.add(_answer('uhd', 3)), isNull);
      expect(pick.add(_answer('fullHd', 60))?.url, _at('fullHd'));
    });

    test('with the wanted quality answering, the others are not waited '
        'for', () {
      final pick = CopyPick([
        _copy('uhd', 2160),
        _copy('fullHd', 1080),
        _copy('hd', 720),
      ], preferred: PreferredQuality.fullHd);

      expect(pick.add(_answer('fullHd', 40))?.url, _at('fullHd'));
    });

    test('a video that was left unfinished goes on from the same copy', () {
      final pick = CopyPick(
        [_copy('fast', 2160), _copy('left', 720)],
        preferred: PreferredQuality.best,
        resume: _at('left'),
      );

      // Sharper and faster, but not the file that was being watched.
      expect(pick.add(_answer('fast', 4)), isNull);
      expect(pick.add(_answer('left', 200))?.url, _at('left'));
    });

    test('if that copy is gone, the best of the others takes over', () {
      final pick = CopyPick(
        [_copy('left', 720), _copy('slow', 1080), _copy('fast', 1080)],
        preferred: PreferredQuality.best,
        resume: _at('left'),
      );

      expect(pick.add(_answer('fast', 4)), isNull);
      expect(pick.add(_silent('left'))?.url, _at('fast'));
    });

    test('when no more answers come, the best that answered is taken', () {
      final pick = CopyPick([
        _copy('uhd', 2160),
        _copy('slow', 720),
        _copy('fast', 720),
      ], preferred: PreferredQuality.best);

      expect(pick.add(_answer('slow', 300)), isNull);
      expect(pick.add(_answer('fast', 20)), isNull);
      expect(pick.complete, isFalse);
      // Time is up for "uhd".
      expect(pick.settle()?.url, _at('fast'));
      expect(pick.answered, 2);
    });

    test('if nothing answered there is nothing to take', () {
      final pick = CopyPick([
        _copy('a', 1080),
        _copy('b', 1080),
      ], preferred: PreferredQuality.best);

      expect(pick.add(_silent('a')), isNull);
      expect(pick.add(_silent('b')), isNull);
      expect(pick.complete, isTrue);
      expect(pick.settle(), isNull);
      expect(pick.answered, 0);
    });
  });

  group('chooseCopy', () {
    late LocalServer server;

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

    PlayCandidate at(String path, [int? height]) =>
        PlayCandidate(server.url(path), height: height);

    CopyProber prober({Duration timeout = const Duration(seconds: 2)}) {
      final prober = CopyProber(
        isAllowedHost: (host) => host == '127.0.0.1',
        timeout: timeout,
      );
      addTearDown(prober.close);
      return prober;
    }

    setUp(() async => server = await LocalServer.start());
    tearDown(() => server.close());

    test('takes the fastest copy without waiting for the slow one', () async {
      video('/slow.mkv', delay: const Duration(milliseconds: 1500));
      video('/fast.mkv', delay: const Duration(milliseconds: 20));
      final watch = Stopwatch()..start();

      final choice = await chooseCopy(prober(), [
        at('/slow.mkv', 1080),
        at('/fast.mkv', 1080),
      ]);

      expect(choice.url, server.url('/fast.mkv'));
      expect(choice.address, server.url('/fast.mkv'));
      expect(choice.answeredIn, lessThan(const Duration(seconds: 1)));
      expect((choice.asked, choice.answered), (2, 1));
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test(
      'waits for the sharper copy, and takes it though it is slower',
      () async {
        video('/uhd.mkv', delay: const Duration(milliseconds: 300));
        video('/hd.mkv', delay: const Duration(milliseconds: 10));

        final choice = await chooseCopy(prober(), [
          at('/hd.mkv', 720),
          at('/uhd.mkv', 2160),
        ]);
        expect(choice.url, server.url('/uhd.mkv'));
        expect((choice.asked, choice.answered), (2, 2));

        // Unless 720p is what is wanted.
        final wanted = await chooseCopy(prober(), [
          at('/hd.mkv', 720),
          at('/uhd.mkv', 2160),
        ], preferred: PreferredQuality.hd);
        expect(wanted.url, server.url('/hd.mkv'));
      },
    );

    test('a copy that is gone is passed over', () async {
      video('/there.mkv', delay: const Duration(milliseconds: 100));

      final choice = await chooseCopy(prober(), [
        at('/gone.mkv', 2160),
        at('/there.mkv', 720),
      ]);

      expect(choice.url, server.url('/there.mkv'));
      expect((choice.asked, choice.answered), (2, 1));
    });

    test('goes on from the copy that was left, if it answers', () async {
      video('/left.mkv', delay: const Duration(milliseconds: 200));
      video('/fast.mkv');
      final copies = [at('/fast.mkv', 2160), at('/left.mkv', 720)];

      final same = await chooseCopy(
        prober(),
        copies,
        resume: server.url('/left.mkv'),
      );
      expect(same.url, server.url('/left.mkv'));

      // The copy that was left is gone: the other one takes over.
      server.routes.remove('/left.mkv');
      final other = await chooseCopy(
        prober(),
        copies,
        resume: server.url('/left.mkv'),
      );
      expect(other.url, server.url('/fast.mkv'));
    });

    test('a copy that needs a session is asked with its headers, and '
        'played with them', () async {
      server.routes['/private.mkv'] = (request) async {
        final allowed = request.headers.value('x-emby-token') == 'token-1';
        request.response.statusCode = allowed
            ? HttpStatus.partialContent
            : HttpStatus.unauthorized;
        await request.response.close();
      };
      const session = {'X-Emby-Token': 'token-1'};
      final copy = at('/private.mkv');

      final refused = await chooseCopy(prober(), [copy]);
      expect(refused.answeredIn, isNull);
      expect(refused.headers, isEmpty);
      // Said, so that the session can be signed in for afresh.
      expect(refused.refused, [copy.url]);

      final choice = await chooseCopy(
        prober(),
        [copy],
        headers: {copy.url: session},
      );
      expect(choice.answeredIn, isNotNull);
      expect(choice.address, copy.url);
      expect(choice.headers, session);
      expect(choice.refused, isEmpty);
    });

    test('a session does not follow a redirect to another host', () async {
      video('/video.mkv');
      final elsewhere = server.url('/video.mkv').replace(host: 'localhost');
      server.redirect('/private.mkv', '$elsewhere');
      final both = CopyProber(
        isAllowedHost: {'127.0.0.1', 'localhost'}.contains,
      );
      addTearDown(both.close);
      final copy = at('/private.mkv');

      final choice = await chooseCopy(
        both,
        [copy],
        headers: {
          copy.url: {'X-Emby-Token': 'token-1'},
        },
      );

      expect(choice.address, elsewhere);
      // Neither the ping nor the player carries it there.
      expect(choice.headers, isEmpty);
      final asked = server.requests.map(
        (request) => (request.uri.path, request.headers.value('x-emby-token')),
      );
      expect(asked, [('/private.mkv', 'token-1'), ('/video.mkv', null)]);
    });

    test('a single address is asked too, for where it leads', () async {
      video('/video.mkv');
      server.redirect('/play/42', '/video.mkv');

      final choice = await chooseCopy(prober(), [at('/play/42')]);

      expect(choice.url, server.url('/play/42'));
      expect(choice.address, server.url('/video.mkv'));
      expect((choice.asked, choice.answered), (1, 1));
    });

    test('if no server answers, the first copy is opened unchecked', () async {
      video('/late.mkv', delay: const Duration(seconds: 2));

      final choice = await chooseCopy(
        prober(timeout: const Duration(milliseconds: 200)),
        [at('/late.mkv', 1080), at('/gone.mkv', 1080)],
      );

      // The player then reports what is wrong with it.
      expect(choice.url, server.url('/late.mkv'));
      expect(choice.address, server.url('/late.mkv'));
      expect(choice.answeredIn, isNull);
      expect((choice.asked, choice.answered), (2, 0));
    });

    test('a copy that is redirected away is never opened', () async {
      final elsewhere = server.url('/video.mkv').replace(host: 'localhost');
      server
        ..redirect('/away.mkv', '$elsewhere')
        ..redirect('/loop.mkv', '/loop.mkv');
      video('/video.mkv');

      // The other copy is taken ...
      final choice = await chooseCopy(prober(), [
        at('/away.mkv', 2160),
        at('/gone.mkv', 1080),
      ]);
      expect(choice.url, server.url('/gone.mkv'));

      // ... and with no other copy, nothing is played.
      await expectLater(
        chooseCopy(prober(), [at('/away.mkv'), at('/loop.mkv')]),
        throwsA(
          isA<PlaybackBlocked>().having(
            (blocked) => blocked.message,
            'message',
            'the server redirects this video to an address that is not one '
                'of your sources.',
          ),
        ),
      );
      expect(
        server.requests.where((request) => request.uri.path == '/video.mkv'),
        isEmpty,
        reason: 'the target is not asked',
      );
    });
  });

  group('the queue', () {
    late SourceStore sources;
    var ids = 0;

    Source source(String id, {SourceType type = SourceType.h5ai}) => Source(
      id: id,
      name: 'Server $id',
      type: type,
      category: SourceCategory.mixed,
      baseUrls: [Uri.parse('http://10.0.0.1/$id/')],
    );

    TitleCopy copy(
      String on, {
      int? height,
      int? season,
      int? episode,
      int? part,
      ExtraKind? extra,
      String? url,
    }) {
      final id = ++ids;
      return TitleCopy(
        fileId: id,
        sourceId: on,
        name: 'file$id.mkv',
        path: 'Movies',
        url: Uri.parse(url ?? 'http://10.0.0.1/$on/file$id.mkv'),
        height: height,
        season: season,
        episode: episode,
        part: part,
        extra: extra,
      );
    }

    setUp(() {
      sources = SourceStore(
        starter: [
          source('a'),
          source('b'),
          source('emby', type: SourceType.emby),
        ],
      );
    });

    test('a film can be played from every copy of it, the chosen one '
        'first', () {
      final hd = copy('a', height: 720);
      final uhd = copy('b', height: 2160);
      final fullHd = copy('a', height: 1080);
      final all = [
        hd,
        uhd,
        fullHd,
        copy('b', height: 1080, extra: ExtraKind.trailer),
        copy('a', height: 2160, url: 'ftp://10.0.0.1/a/film.mkv'),
      ];

      // The trailer and the copy at no web address are no alternatives.
      expect(sameVideo(hd, all, sources), [hd, uhd, fullHd]);
      // A copy on a media server is one: the app signs in for it.
      final onEmby = copy('emby', height: 480);
      expect(sameVideo(hd, [...all, onEmby], sources), [
        hd,
        uhd,
        fullHd,
        onEmby,
      ]);
      expect(sameVideo(hd, all, sources, preferred: PreferredQuality.fullHd), [
        hd,
        fullHd,
        uhd,
      ]);
      expect(sameVideo(all[3], all, sources), [all[3]]);
    });

    test('the parts of a film in two files are two videos', () {
      final first = copy('a', part: 1);
      final second = copy('a', part: 2);
      final firstAgain = copy('b', part: 1);

      expect(sameVideo(first, [first, second, firstAgain], sources), [
        first,
        firstAgain,
      ]);
    });

    test('every episode of the queue has its own copies to choose from', () {
      final one = copy('a', height: 1080, season: 1, episode: 1);
      final oneAgain = copy('b', height: 1080, season: 1, episode: 1);
      final two = copy('a', height: 720, season: 1, episode: 2);
      final twoAgain = copy('b', height: 2160, season: 1, episode: 2);
      final all = [one, oneAgain, two, twoAgain];

      final queue = playQueue(
        name: 'The Bay',
        copy: one,
        copies: all,
        sources: sources,
      );

      expect(queue.map((entry) => entry.title), [
        'The Bay · S1 · E1',
        'The Bay · S1 · E2',
      ]);
      expect(queue[0].candidates.map((each) => each.url), [
        one.url,
        oneAgain.url,
      ]);
      // The next episode's first choice is on the server of the one that
      // was started (see queueFrom); the other copy is there to be asked.
      expect(queue[1].candidates.map((each) => each.url), [
        two.url,
        twoAgain.url,
      ]);
      expect(queue[1].candidates.map((each) => each.height), [720, 2160]);
    });

    test('a copy picked from the list is played from there and nowhere '
        'else; what follows it is chosen as always', () {
      final one = copy('a', season: 1, episode: 1);
      final oneAgain = copy('b', season: 1, episode: 1);
      final two = copy('a', season: 1, episode: 2);
      final twoAgain = copy('b', season: 1, episode: 2);

      final queue = playQueue(
        name: 'The Bay',
        copy: oneAgain,
        copies: [one, oneAgain, two, twoAgain],
        sources: sources,
        exact: true,
      );

      expect(queue[0].candidates.map((each) => each.url), [oneAgain.url]);
      expect(queue[1].candidates, hasLength(2));
    });

    test('a film is called by its name and year', () {
      final film = copy('a');
      final queue = playQueue(
        name: 'Vivarium',
        year: 2019,
        copy: film,
        copies: [film],
        sources: sources,
      );

      expect(queue.single.title, 'Vivarium (2019)');
      expect(queue.single.candidates.single.url, film.url);
      expect(PlayEntry.url(film.url).candidates.single.url, film.url);
    });
  });
}
