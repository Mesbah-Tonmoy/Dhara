import 'dart:io';

import 'package:dhara/features/metadata/release_name.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  VideoIdentity identify(String path, String name, {int videos = 1}) =>
      identifyVideo(
        path: path,
        name: name,
        videosInFolder: videos,
        latestYear: 2027,
      );

  test('reads the real paths and names of the sample as checked by hand', () {
    final lines = File(
      'test/fixtures/names/library_names.tsv',
    ).readAsLinesSync();
    var rows = 0;
    for (final line in lines) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      final cells = line.split('\t');
      while (cells.length < 10) {
        cells.add('');
      }
      final found = identify(cells[0], cells[1], videos: int.parse(cells[2]));
      final got = [
        found.kind.name,
        found.title,
        found.year ?? '',
        found.season ?? '',
        found.episode ?? '',
        found.part ?? '',
        found.extra?.name ?? '',
      ].join(' | ');
      expect(
        got,
        cells.sublist(3, 10).join(' | '),
        reason: '${cells[0]} / ${cells[1]}',
      );
      rows++;
    }
    expect(rows, greaterThan(150));
  });

  group('films', () {
    test('a folder named like a film names the one video in it', () {
      final plain = identify(
        'Kolkata Bangla Movies/(2011)/Necklace (2011)',
        'necklace.mkv',
      );
      expect(plain.kind, TitleKind.movie);
      expect((plain.title, plain.year), ('Necklace', 2011));
      expect(plain.key, 'm|necklace|2011');
      expect(plain.altTitle, isNull);

      final joined = identify(
        'English Movies/(2009)/The Unborn (2009)',
        'TheUnborn-aXXo.avi',
      );
      expect((joined.title, joined.year), ('The Unborn', 2009));
      expect(joined.altTitle, 'TheUnborn-aXXo');

      final foreign = identify(
        'Foreign Language Movies/French Language/Shall We Kiss (2007) (France)',
        "Un baiser s'il vous plaît.avi",
      );
      expect((foreign.title, foreign.year), ('Shall We Kiss', 2007));
      expect(foreign.altTitle, "Un baiser s'il vous plaît");
      expect(foreign.key, 'm|shall we kiss|2007');
    });

    test('what the file does not say about the copy, the folder may', () {
      final found = identify(
        'English Movies/(2019)/Vivarium (2019) 720p [Dual Audio]',
        'vivarium.mkv',
      );
      expect(found.height, 720);
      expect(found.audio, MultiAudio.dual);

      final file = identify(
        'English Movies/(2019)/Vivarium (2019) 720p [Dual Audio]',
        'Vivarium (2019) 1080p WEBRip x265 [Hindi+English] -GRP.mkv',
      );
      expect(file.height, 1080);
      expect(file.source, VideoSource.webRip);
      expect(file.codec, VideoCodec.hevc);
      expect(file.languages, ['Hindi', 'English']);
      expect(file.group, 'GRP');
    });

    test('folders that only sort films do not name them', () {
      final expected = {
        ('Movies/English', 'Stillwater (2018) 1080p WEBDL.mkv'): (
          'Stillwater',
          2018,
        ),
        ('English Movies/(2014)', 'April.Rain.2014.720p.BluRay.x264.YIFY.mp4'):
            ('April Rain', 2014),
        ('Hindi-2021', 'Some Film (2020) 720p.mkv'): ('Some Film', 2020),
        ('English 2014', 'Cat Run 2 (2014) 720p BluRay.mkv'): (
          'Cat Run 2',
          2014,
        ),
        ('', 'Stillwater (2018) 1080p WEBDL.mkv'): ('Stillwater', 2018),
      };
      for (final MapEntry(key: (path, name), value: (title, year))
          in expected.entries) {
        final found = identify(path, name, videos: 40);
        expect(found.kind, TitleKind.movie, reason: name);
        expect((found.title, found.year), (title, year), reason: name);
        expect(found.altTitle, isNull, reason: name);
      }
    });

    test('a folder from another year is a collection', () {
      final found = identify('Best of Bond (2012)', 'Dr. No (1962) 720p.mkv');
      expect((found.title, found.year), ('Dr. No', 1962));
      expect(found.altTitle, 'Best of Bond');
    });

    test('a folder with several videos must be related to the file', () {
      const folder = 'Movies/The Dark Knight Trilogy (2005)';
      final begins = identify(
        folder,
        'Batman Begins (2005) 720p.mkv',
        videos: 3,
      );
      expect((begins.title, begins.year), ('Batman Begins', 2005));
      expect(begins.altTitle, 'The Dark Knight Trilogy');

      // Two copies of one film in its folder.
      final copy = identify(
        'English Movies/(2009)/Transformers-Revenge of the Fallen (2009) 720p',
        'Transformers 2 (2009) 720p BluRay.mkv',
        videos: 2,
      );
      expect(copy.title, 'Transformers-Revenge of the Fallen');
      expect(copy.altTitle, 'Transformers 2');

      // A file without a year, next to others.
      final stray = identify(
        'Music Video/Hindi/Nora Fatehi (2018) Video Song Collections',
        'Naah.mkv',
        videos: 6,
      );
      expect(stray.kind, TitleKind.other);
      expect(stray.title, 'Naah');
    });

    test('copies on different servers get the same key', () {
      final keys = {
        identify(
          'English Movies/(2019)/Vivarium (2019) 720p [Dual Audio]',
          'Vivarium (2019) 720p BluRay x264 ESub [Dual Audio]'
              '[Hindi 2.0+English 5.1] -mkvC.mkv',
        ).key,
        identify(
          'Movies/English',
          'Vivarium (2019) 1080p WEBRip.mkv',
          videos: 265,
        ).key,
        identify('Movie/English', 'vivarium.2019.720p.bluray.mkv').key,
      };
      expect(keys, {'m|vivarium|2019'});

      expect(
        identify(
          'Movies',
          'Godzilla.Vs..Kong.2021.1080p.BluRay.x264-[YTS.MX].mp4',
        ).key,
        identify(
          '3D Movies/Godzilla vs. Kong (2021) 1080p [3D]',
          'whatever.mp4',
        ).key,
      );
    });

    test('a film without a year has a key without one', () {
      expect(
        identify('Movies/Bangla BD', 'Alangkar DVDRip.mp4').key,
        'm|alangkar|',
      );
    });

    test('trailers, samples and CD parts keep the title of their film', () {
      final trailer = identify(
        'Movies/See No Evil 2 (2014)',
        'Trailer - See No Evil 2 (2014).mp4',
        videos: 2,
      );
      expect(trailer.kind, TitleKind.movie);
      expect(trailer.key, 'm|see no evil 2|2014');
      expect(trailer.extra, ExtraKind.trailer);

      // The trailer says nothing of the film; its folder does.
      final unnamed = identify(
        'Movies/The Trip to Italy (2014)',
        'Official Trailer.mp4',
        videos: 2,
      );
      expect(unnamed.key, 'm|the trip to italy|2014');
      expect(unnamed.extra, ExtraKind.trailer);

      final part = identify(
        'Kolkata Bangla Movies/Satyajit Ray Films/'
            '(1973) Ashani Sanket (Distant Thunder)/'
            '(1973) Ashani Sanket (Distant Thunder)-CD2',
        'Ashani Sanket AKA Distant Thunder-CD2(1973).avi',
      );
      expect((part.title, part.year, part.part), ('Ashani Sanket', 1973, 2));
      expect(part.altTitle, 'Ashani Sanket AKA Distant Thunder');
    });
  });

  group('shows', () {
    test('the file names the show and the episode', () {
      final found = identify(
        'tvshows/Grimm/Grimm Season 3',
        'Grimm Season-03 Episode-17 Synchronicity.mp4',
        videos: 22,
      );
      expect(found.kind, TitleKind.series);
      expect(found.title, 'Grimm');
      expect(found.key, 's|grimm');
      expect((found.season, found.episode), (3, 17));
      expect(found.episodeTitle, 'Synchronicity');
      expect(found.altTitle, isNull);
    });

    test('a show has one key, whatever the season and the spelling', () {
      final keys = {
        identify(
          'Tv Show/English/Marvels Agents of S H I E L D Season 06 (2019) '
              'Completed',
          'Marvels Agents of S.H.I.E.L.D S06E02 1080p WEBRip.mkv',
        ).key,
        identify(
          'TV/Marvels Agents of S.H.I.E.L.D./Season 1',
          'S01E05.mkv',
        ).key,
        identify('TV', 'marvels.agents.of.s.h.i.e.l.d.s02e01.720p.mkv').key,
      };
      expect(keys, {'s|marvels agents of shield'});

      final friends = identify(
        'Music Videos/TV show/FRIENDS FULL SEASONS 1 - 10 (Complete)/'
            'F R I E N D S Season 9',
        'Friends Season-09 Episode-11 The One Where Rachel Goes Back.avi',
      );
      expect(friends.key, 's|friends');
      expect(friends.altTitle, isNull);
    });

    test('the year of a show may be the year of the season', () {
      final found = identify(
        'Tv Show/English/Marvels Agents of S H I E L D Season 06 (2019) '
            'Completed',
        'Marvels Agents of S.H.I.E.L.D S06E02 1080p WEBRip.mkv',
      );
      expect(found.year, 2019);
      expect(found.key, isNot(contains('2019')));
    });

    test('folders name the show and the season when the file does not', () {
      final expected = {
        ('Tv Show/Bangla/Money Honey (2019) S01 Complete', 'EP02.mp4'): (
          'Money Honey',
          1,
          2,
          null,
        ),
        ('TV/Breaking Bad/Season 1', 'S01E02.mkv'): (
          'Breaking Bad',
          1,
          2,
          null,
        ),
        ('TV/Breaking Bad/Season 2', '03 - Bit by a Dead Bee.mkv'): (
          'Breaking Bad',
          2,
          3,
          'Bit by a Dead Bee',
        ),
        ('TV/Breaking Bad/Season 2', '03.mkv'): ('Breaking Bad', 2, 3, null),
        ('tvshows/Show Season 2', 'Show Episode 5.mkv'): ('Show', 2, 5, null),
        ('tvshows/Show Season 2', 'Episode 5.mkv'): ('Show', 2, 5, null),
      };
      for (final MapEntry(
            key: (path, name),
            value: (title, season, episode, words),
          )
          in expected.entries) {
        final found = identify(path, name, videos: 12);
        expect(found.kind, TitleKind.series, reason: name);
        expect(found.title, title, reason: name);
        expect((found.season, found.episode), (season, episode), reason: name);
        expect(found.episodeTitle, words, reason: name);
      }
    });

    test('anime numbered straight through has no season', () {
      final found = identify(
        'Anime/Frieren',
        '[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv',
        videos: 28,
      );
      expect(found.kind, TitleKind.series);
      expect(found.title, 'Sousou no Frieren');
      expect(found.altTitle, 'Frieren');
      expect((found.season, found.episode), (null, 5));
      expect(found.height, 1080);
    });

    test('a number after the name of the folder is an episode', () {
      final found = identify(
        'Bangla Drama and Telifilm/Drama/up to 2012/vober_hat',
        'vober_hat96.wmv',
        videos: 21,
      );
      expect(found.kind, TitleKind.series);
      expect(found.key, 's|vober hat');
      expect((found.season, found.episode), (null, 96));

      // One digit is a sequel.
      final sequel = identify('Movies/Toy Story', 'Toy Story 3.mkv', videos: 3);
      expect(sequel.kind, TitleKind.movie);
      expect(sequel.title, 'Toy Story 3');
    });

    test('a number after a dash in the folder of a film is no episode', () {
      final found = identify(
        'English Movies/(2015)/Fast (2015) 720p',
        'Fast - 10 720p.mkv',
      );
      expect(found.kind, TitleKind.movie);
      expect((found.title, found.year, found.episode), ('Fast', 2015, null));
    });

    test('without a name for the show it is not a show', () {
      final found = identify('Tv Show/English', 'S01E02.mkv', videos: 9);
      expect(found.kind, TitleKind.other);
      expect(found.title, 'S01E02.mkv');
      expect(found.key, isNull);
    });

    test('a file of a season without an episode is neither', () {
      final found = identify(
        'tvshows/Baywatch Series/Baywatch S08/Extras',
        'Baywatch S08 Extras DVDRip.avi',
      );
      expect(found.kind, TitleKind.other);
      expect(found.title, 'Baywatch');
    });

    test('in a TV folder, a video without an episode is a film', () {
      final found = identify(
        'Tv Show/Bangla',
        'Bokhate (2016) 720p HDRip.MP4',
        videos: 14,
      );
      expect(found.kind, TitleKind.movie);
      expect(found.key, 'm|bokhate|2016');
    });
  });

  group('other videos', () {
    test('clips, songs and tutorials are not titles', () {
      final expected = {
        ('Fun Zone/Funny Vedio/WMV', 'Coins.wmv'): 'Coins',
        ('Mobile/Mobile Mp4/Funny', 'Maps on Vodafone.mp4'): 'Maps on Vodafone',
        ('Music Video/Hindi', 'Some Singer - Some Song (2014).mp4'):
            'Some Singer - Some Song',
        ('Tutorials/Photoshop', 'Lesson 01.mp4'): 'Lesson 01',
        ('Software/Converter', 'How to install.mp4'): 'How to install',
      };
      for (final MapEntry(key: (path, name), value: title)
          in expected.entries) {
        final found = identify(path, name, videos: 30);
        expect(found.kind, TitleKind.other, reason: name);
        expect(found.title, title, reason: name);
        expect(found.key, isNull, reason: name);
      }
    });

    test('a trailer among clips is still not a title', () {
      final found = identify(
        'Mobile/Mobile Mp4/Hindi (Mp4)',
        'Don 2 - Theatrical Trailer [Funmaza.com].mp4',
        videos: 148,
      );
      expect(found.kind, TitleKind.other);
      expect(found.title, 'Don 2');
      expect(found.extra, ExtraKind.trailer);
    });

    test('what is named like a film is one, wherever it is', () {
      // ICC FTP S3 keeps films below "Music Videos".
      final inFolder = identify(
        'Music Videos/Need for Speed (2014) (10GB)',
        'Need for Speed (2014) 1080p.mkv',
        videos: 2,
      );
      expect(inFolder.kind, TitleKind.movie);
      expect(inFolder.key, 'm|need for speed|2014');

      final byName = identify(
        'Music Videos/English 2014',
        'Cat Run 2 (2014) 720p BluRay.mkv',
        videos: 30,
      );
      expect(byName.kind, TitleKind.movie);
    });

    test('the innermost sorting folder decides', () {
      final film = identify(
        'Music Videos/English Movies/United 93 (2006)',
        'United 93.mp4',
      );
      expect(film.kind, TitleKind.movie);

      final show = identify(
        'Music Videos/TV show/Some Show',
        'Some Show S01E01.avi',
      );
      expect(show.kind, TitleKind.series);

      // A film's own folder is not asked: this is not music.
      final lyrics = identify(
        'English Movies/(2007)/Music and Lyrics (2007) 720p',
        'Music.and.Lyrics.2007.720p.BluRay.x264.YIFY.mp4',
      );
      expect(lyrics.kind, TitleKind.movie);
      expect(lyrics.title, 'Music and Lyrics');
    });
  });

  group('normalizeTitle', () {
    test('makes different spellings of one name equal', () {
      final expected = {
        'The Dark Knight': 'the dark knight',
        "Don't Be a Menace": 'dont be a menace',
        'Don’t Be a Menace': 'dont be a menace',
        'Les Misérables': 'les miserables',
        'Pelé-Birth of a Legend': 'pele birth of a legend',
        'Straße': 'strasse',
        'S.H.I.E.L.D.': 'shield',
        'S H I E L D': 'shield',
        'E.T. the Extra-Terrestrial': 'et the extra terrestrial',
        'E.T. The Extra-Terrestrial': 'et the extra terrestrial',
        'Fast & Furious': 'fast and furious',
        'Hitman-Agent 47': 'hitman agent 47',
        'Godzilla vs. Kong': 'godzilla vs kong',
        'Godzilla Vs Kong': 'godzilla vs kong',
        '  Empathy,   Inc. ': 'empathy inc',
        '3.10 to Yuma': '3 10 to yuma',
        '': '',
        '!!!': '',
      };
      for (final MapEntry(key: title, value: plain) in expected.entries) {
        expect(normalizeTitle(title), plain, reason: title);
      }
    });

    test('keeps letters of other scripts', () {
      expect(normalizeTitle('Михалков 12'), 'михалков 12');
      expect(normalizeTitle('মরীচিকা'), isNotEmpty);
    });
  });

  test('never throws, whatever the path and the name', () {
    for (final (path, name) in [
      ('', ''),
      ('/', '.mkv'),
      ('///', '   '),
      ('(((', ')))'),
      ('[', ']'),
      ('a/b/c/d/e/f/g/h', 'S01E02.mkv'),
      ('Season 1/Season 2', '03.mkv'),
      ('(2019)/(2019)', '(2019).mkv'),
      ('${'x/' * 500}y', '${'a' * 3000}.mkv'),
    ]) {
      expect(
        () => identify(path, name),
        returnsNormally,
        reason: '$path $name',
      );
      expect(
        () => identify(path, name, videos: 0),
        returnsNormally,
        reason: '$path $name',
      );
    }
  });
}
