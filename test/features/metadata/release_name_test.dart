import 'package:dhara/features/metadata/release_name.dart';
import 'package:flutter_test/flutter_test.dart';

/// Most names below are real ones, seen on DhakaFlix 7 and the ICC FTP
/// servers in November 2026.
void main() {
  ReleaseName parse(String name) => parseReleaseName(name, latestYear: 2027);

  void expectTitles(Map<String, (String, int?)> expected) {
    for (final MapEntry(key: name, value: (title, year)) in expected.entries) {
      final parsed = parse(name);
      expect(parsed.title, title, reason: name);
      expect(parsed.year, year, reason: name);
    }
  }

  group('title and year', () {
    test('names written with dots', () {
      expectTitles({
        'Witness.Infection.2021.720p.WEBRip.800MB.x264-GalaxyRG.mkv': (
          'Witness Infection',
          2021,
        ),
        'Pride.And.Prejudice.And.Zombies.2016.720p.BRRip.950MB.MkvCage.mkv': (
          'Pride And Prejudice And Zombies',
          2016,
        ),
        'We.Need.to.Talk.About.Kevin.2011.720p.BrRip.x264.YIFY.mp4': (
          'We Need to Talk About Kevin',
          2011,
        ),
        'The.Dark.Hour.2006.Spanish.DVDRip.XviD.ESub-RedBlade.avi': (
          'The Dark Hour',
          2006,
        ),
        'Godzilla.Vs..Kong.2021.1080p.3D.BluRay.HSBS.x264-[YTS.MX].mp4': (
          'Godzilla Vs Kong',
          2021,
        ),
        'The.siege.of.jadotville.2016.720p.webrip.x264-NBY.mkv': (
          'The siege of jadotville',
          2016,
        ),
      });
    });

    test('names written with spaces and the year in brackets', () {
      expectTitles({
        'Vivarium (2019) 720p BluRay x264 ESub [Dual Audio]'
            '[Hindi 2.0+English 5.1] -mkvC.mkv': (
          'Vivarium',
          2019,
        ),
        'The LEGO Batman Movie (2017) 1080p 3D HSBS BluRay.mp4': (
          'The LEGO Batman Movie',
          2017,
        ),
        'Learning To Drive  (2014) 1080p BluRay.mkv': (
          'Learning To Drive',
          2014,
        ),
        'Blood Night The Legend Of Mary Hatchet (2009).avi': (
          'Blood Night The Legend Of Mary Hatchet',
          2009,
        ),
        'MacGruber (2010).avi': ('MacGruber', 2010),
        'Ashani Sanket AKA Distant Thunder(1973).avi': (
          'Ashani Sanket AKA Distant Thunder',
          1973,
        ),
      });
    });

    test('a bare year, with words between it and the tags', () {
      expectTitles({
        'Pearl in Paradise 2018 Hallmark 720p HDTV X264 Solar.mp4': (
          'Pearl in Paradise',
          2018,
        ),
        'The Closed Circuit 2013 720p BluRay 850MB-Micromkv.mkv': (
          'The Closed Circuit',
          2013,
        ),
      });
    });

    test('spaces in the title and dots among the tags', () {
      expectTitles({
        'Baby and Me.2008.DVDRip.avi': ('Baby and Me', 2008),
        'The Scorpion King 2 Rise of a Warrior 2008.720p.BrRip.x264.YIFY.mp4': (
          'The Scorpion King 2 Rise of a Warrior',
          2008,
        ),
        'The Terror Live, 2013.720P.BrRip.x264.mp4': ('The Terror Live', 2013),
        'The Art of Getting By.2011.x264.720p.YIFY.mp4': (
          'The Art of Getting By',
          2011,
        ),
      });
      expect(
        parse(
          'Bad Lieutenant - New Orleans 2009.720p.BrRip.x264.YIFY.mp4',
        ).group,
        'YIFY',
      );
    });

    test('the year in square brackets', () {
      expectTitles({
        'Angels In Stardust [2014] WEBRip 720P H264-Masta.mp4': (
          'Angels In Stardust',
          2014,
        ),
        "Satan's.Little.Helper[2004]DvDrip[Eng]-aXXo.avi": (
          "Satan's Little Helper",
          2004,
        ),
        '[2014] Angels In Stardust WEBRip.mp4': ('Angels In Stardust', 2014),
      });
    });

    test('titles that are or begin with numbers', () {
      expectTitles({
        '127.Hours.2010.720p.BrRip.x264.YIFY.mp4': ('127 Hours', 2010),
        '300.Rise.of.an.Empire.2014.1080p.3D.HSBS.BluRay.x264.YIFY.mp4': (
          '300 Rise of an Empire',
          2014,
        ),
        '400.Bullets.2021.720p.BluRay.800MB.x264-GalaxyRG.mkv': (
          '400 Bullets',
          2021,
        ),
        '2 Days in New York (2012) BluRay 720p 700MB Ganool.AG.mkv': (
          '2 Days in New York',
          2012,
        ),
        '31 (2016) 720p BluRay.mkv': ('31', 2016),
        '10x10 (2018) 720p BluRay x264 ESub [Dual Audio]'
            '[Hindi 2.0+English 5.1] -MsMod.mkv': (
          '10x10',
          2018,
        ),
        '3.10 to Yuma (2007) 720p BluRay x264 ESub [Dual Audio]'
            '[Hindi 2.0+English 5.1] -mkvC.mkv': (
          '3.10 to Yuma',
          2007,
        ),
      });
    });

    test('titles that look like a year', () {
      expectTitles({
        '1917.2019.1080p.BluRay.x264.mkv': ('1917', 2019),
        '2012.2009.720p.BluRay.mkv': ('2012', 2009),
        '2012 (2009) 720p.mkv': ('2012', 2009),
        '2012.720p.BluRay.mkv': ('2012', null),
        // 2049 has not come yet, so it cannot be the year.
        'Blade.Runner.2049.2017.1080p.BluRay.mkv': ('Blade Runner 2049', 2017),
        'Blade Runner 2049 (2017) 1080p.mkv': ('Blade Runner 2049', 2017),
        '2001.A.Space.Odyssey.1968.720p.mkv': ('2001 A Space Odyssey', 1968),
      });
    });

    test('no year: the title ends at the first certain tag', () {
      expectTitles({
        'Honeydew.720p.BluRay.800MB.x264-GalaxyRG.mkv': ('Honeydew', null),
        'Love.Phobia.HDTV.720p.800MB-PaHe.in.mkv': ('Love Phobia', null),
        'Movie.Name.DUBBED.720p.BluRay.mkv': ('Movie Name', null),
        'necklace.mkv': ('necklace', null),
        "Un baiser s'il vous plaît.avi": ("Un baiser s'il vous plaît", null),
        'Facebook on Vodafone - Zoozoos poking each other.flv': (
          'Facebook on Vodafone - Zoozoos poking each other',
          null,
        ),
      });
    });

    test('a year among the tags is still the year', () {
      expectTitles({
        'Some.Movie.720p.2019.BluRay.mkv': ('Some Movie', 2019),
        'Ong Bak [BRRip 720p] (2003).mkv': ('Ong Bak', 2003),
      });
    });

    test('words that are tags elsewhere stay in a title', () {
      expectTitles({
        'Cam.2018.1080p.NF.WEB-DL.mkv': ('Cam', 2018),
        'Step Up 3D (2010) 720p BluRay.mkv': ('Step Up 3D', 2010),
        'The English Patient (1996) 720p.mkv': ('The English Patient', 1996),
        'Broken.English.720p.BluRay.mkv': ('Broken English', null),
        'Web of Lies (2009).avi': ('Web of Lies', 2009),
      });
    });

    test('dots that belong to the words', () {
      expectTitles({
        'E.T.The.Extra-Terrestrial.1982.720p.BRRip.1GB.MkvCage.mkv': (
          'E.T. The Extra-Terrestrial',
          1982,
        ),
        'A.I.Artificial.Intelligence.2001.720p.BluRay.x264.mkv': (
          'A.I. Artificial Intelligence',
          2001,
        ),
        'A.Stranger.Among.the.Living.2019.720p.AMZN.WEBRip.800MB.x264-GalaxyRG'
            '.mkv': (
          'A Stranger Among the Living',
          2019,
        ),
        'Marvels Agents of S.H.I.E.L.D (2019) 1080p WEBRip.mkv': (
          'Marvels Agents of S.H.I.E.L.D',
          2019,
        ),
        'L.A. Confidential (1997) 720p.mkv': ('L.A. Confidential', 1997),
        "Dr. Bird's Advice for Sad Poets (2021) 720p WEBRip.mkv": (
          "Dr. Bird's Advice for Sad Poets",
          2021,
        ),
      });
    });

    test('hyphens stay as written', () {
      expectTitles({
        'The Twilight Saga-Breaking Dawn - Part 1 (2011) 720p BluRay x264 ESub '
            '[Dual Audio][Hindi 2.0+English 5.1] -mkvC.mkv': (
          'The Twilight Saga-Breaking Dawn - Part 1',
          2011,
        ),
        'Spider-Man.2002.1080p.BluRay.mkv': ('Spider-Man', 2002),
      });
    });

    test('remarks in brackets', () {
      expectTitles({
        'Konkurîto (2004) DVDRip [Concrete].avi': ('Konkurîto', 2004),
        'Parbona Ami Charte Toke  [Bengali] Upscaled DVDRip - ESubs -1.49GB.mkv':
            ('Parbona Ami Charte Toke', null),
        'Ooopss [from www.metacafe.com].mpg': ('Ooopss', null),
        'Local Hero (Drama).mkv': ('Local Hero', null),
        '12 (Н.Михалков).avi': ('12', null),
        'Seven Short Films About (Our) Marriage (2020) 720p WEBRip.mkv': (
          'Seven Short Films About (Our) Marriage',
          2020,
        ),
        '(500) Days of Summer (2009) 720p.mkv': ('(500) Days of Summer', 2009),
        'Bangla Eid Natok (2015) {Eid Ul Adha} Mofij BSC.mp4': (
          'Bangla Eid Natok',
          2015,
        ),
      });
    });

    test('the year in front, as some folders have it', () {
      expectTitles({
        '(1973) Ashani Sanket (Distant Thunder)': ('Ashani Sanket', 1973),
        '1930 - Juno and the Paycock.avi': ('Juno and the Paycock', 1930),
        // No dash: the number is the title.
        '1917 Behind the Scenes.mkv': ('1917 Behind the Scenes', null),
        '(2019)': ('(2019)', 2019),
        '(1960-1994)': ('(1960-1994)', null),
      });
    });

    test('a tag in front is skipped, unless it is all there is', () {
      expectTitles({
        '[SubsPlease] Some Show (2021) [1080p].mkv': ('Some Show', 2021),
        '[REC] (2007) 720p BluRay.mkv': ('REC', 2007),
        '[REC].mkv': ('REC', null),
      });
    });

    test('folder names', () {
      expectTitles({
        '300-Rise of an Empire (2014) 1080p [3D]': (
          '300-Rise of an Empire',
          2014,
        ),
        'The Girl Who Played with Fire (2009) 720p [Dual Audio]': (
          'The Girl Who Played with Fire',
          2009,
        ),
        'Chez nous (2017) 720p (France)': ('Chez nous', 2017),
        'Godzilla vs. Kong (2021) 1080p [3D]': ('Godzilla vs. Kong', 2021),
        'Empathy, Inc. (2018) 720p WEBRip': ('Empathy, Inc.', 2018),
      });
    });

    test('the cut is not part of the title', () {
      expectTitles({
        'Reindeer Games Directors Cut (2000) BluRay 720p 800MB Ganool.mkv': (
          'Reindeer Games',
          2000,
        ),
        'Aliens.Extended.1986.1080p.BluRay.mkv': ('Aliens', 1986),
        "Alien Director's Cut (1979) 1080p.mkv": ('Alien', 1979),
        // Nothing would be left.
        'Unrated (2009) 720p.mkv': ('Unrated', 2009),
      });
    });

    test('letters outside ASCII', () {
      expectTitles({
        'Les.Misérables.2012.720p.BRrip.x264.GAZ.YIFY.mp4': (
          'Les Misérables',
          2012,
        ),
        'Dans les forêts de Sibérie (2016) French 720p BluRay x264 ESub-Pahe'
            '.mkv': (
          'Dans les forêts de Sibérie',
          2016,
        ),
        'Pelé Birth of a Legend (2016) 720p BluRay x264 ESub [Dual Audio]'
            '[Hindi 2.0+English 2.0] -ExtraM.mkv': (
          'Pelé Birth of a Legend',
          2016,
        ),
      });
    });

    test('only video extensions are cut off', () {
      expectTitles({
        'Movie (2019).MKV': ('Movie', 2019),
        'Movie (2019).srt': ('Movie', 2019),
        'Mr. Nobody': ('Mr. Nobody', null),
      });
      expect(parse('Movie.Name.2019.720p.nfo').title, 'Movie Name');
    });

    test('invisible characters do not hide a tag', () {
      // A left-to-right mark in front of "Bengali", as on DhakaFlix.
      final parsed = parse(
        'Crisscross (2018) \u200EBengali 720p WEB-DL x264 AAC { TaRa }.mkv',
      );
      expect(parsed.title, 'Crisscross');
      expect(parsed.languages, ['Bengali']);
      expect(parse('Mov\u202Eie (2019).mkv').title, 'Movie');
    });
  });

  group('quality', () {
    test('picture height', () {
      final expected = {
        'A Moment of Innocence (1996) Persian 480p DVDRip x264 ESub.mkv': 480,
        'Captn Sharky (2018) 720P WEBDL.mkv': 720,
        'Stillwater (2018) 1080p WEBDL.mkv': 1080,
        'Bird Karma (2018) 1080 WEBDL.mkv': 1080,
        'Movie (2019) 2160p UHD BluRay x265.mkv': 2160,
        'Movie (2019) 4K WEB-DL.mkv': 2160,
        'Movie.2019.1080i.HDTV.mkv': 1080,
        'MacGruber (2010).avi': null,
        // Not a height anyone uses.
        'Movie (2019) 999p.mkv': null,
      };
      for (final MapEntry(key: name, value: height) in expected.entries) {
        expect(parse(name).height, height, reason: name);
      }
    });

    test('where the copy comes from', () {
      final expected = {
        'Honeydew.2020.720p.BluRay.800MB.x264-GalaxyRG.mkv': VideoSource.bluRay,
        'Papillon.1973.720p.BRRip.MkvCage.mkv': VideoSource.bluRay,
        'Movie (2019) 1080p Blu-Ray x264.mkv': VideoSource.bluRay,
        'The.Maus.2017.720p.NF.WEB-DL.MkvCage.WS.mkv': VideoSource.webDl,
        'Stillwater (2018) 1080p WEBDL.mkv': VideoSource.webDl,
        '6 Balloons (2018) 1080p WEBHD.mkv': VideoSource.webDl,
        'Movie (2019) 1080p WEB DL x264.mkv': VideoSource.webDl,
        'Hellboy The Crooked Man (2024) 720p AMZN-WEB x264 ESub [Dual Audio]'
                '[Hindi 2.0+English 5.1] -mkvC.mkv':
            VideoSource.webDl,
        'Anunnaki (2017) 1080p WEBRip.mkv': VideoSource.webRip,
        'Free Birds (2013) 720p HDRip.mkv': VideoSource.hdRip,
        'Premer Phool (2018) 720p HDTVRip.mkv': VideoSource.hdtv,
        'Love.in.Winterland.2020.720p.HDTV.x264-GalaxyRG.mkv': VideoSource.hdtv,
        'Chaplin (2011) 720p DvDRip.mkv': VideoSource.dvd,
        'Movie.2024.HDCAM.x264.mkv': VideoSource.cam,
        'Movie (2024) 720p HD-TS x264.mkv': VideoSource.cam,
        'MacGruber (2010).avi': null,
      };
      for (final MapEntry(key: name, value: source) in expected.entries) {
        expect(parse(name).source, source, reason: name);
      }
    });

    test('a certain tag beats a loose one', () {
      final parsed = parse('Movie (2019) 1080 BD 720p WEBRip.mkv');
      expect(parsed.height, 720);
      expect(parsed.source, VideoSource.webRip);
    });

    test('video codec', () {
      final expected = {
        'April.Rain.2014.720p.BluRay.x264.YIFY.mp4': VideoCodec.h264,
        'Disney.Presents.Enchanted.2007.720p.BluRay.H264.AAC-RARBG.mp4':
            VideoCodec.h264,
        'Movie.Name.2019.1080p.WEB-DL.DD5.1.H.264-GRP.mkv': VideoCodec.h264,
        'Movie Name (2019) 1080p WEB-DL DD5.1 H.264-GRP.mkv': VideoCodec.h264,
        'The Witch Part 2 The Other One (2022) 1080p BluRay x265 HEVC ESub '
                '[Multi Audio][Hindi 2.0+English 5.1+Korean 5.1] -OlaM.mkv':
            VideoCodec.hevc,
        'Movie.2019.2160p.WEB-DL.H.265-GRP.mkv': VideoCodec.hevc,
        'Ma.Mère.2004.DVDRip.XviD.RoSubbed-GodFront.avi': VideoCodec.xvid,
        'Movie.2003.DVDRip.DivX.avi': VideoCodec.divx,
        'Movie (2023) 1080p WEB-DL AV1.mkv': VideoCodec.av1,
        'Urban Cowboy (1980) 720p BRRip.mp4': null,
      };
      for (final MapEntry(key: name, value: codec) in expected.entries) {
        expect(parse(name).codec, codec, reason: name);
      }
    });

    test('3D copies', () {
      for (final name in [
        'The LEGO Batman Movie (2017) 1080p 3D HSBS BluRay.mp4',
        '300.Rise.of.an.Empire.2014.1080p.3D.HSBS.BluRay.x264.YIFY.mp4',
        'Zootopia (2016) 1080p [3D]',
        'Movie (2016) 1080p Half-SBS BluRay.mkv',
      ]) {
        expect(parse(name).is3d, isTrue, reason: name);
      }
      // "3D" is part of this title; the copy need not be 3D.
      expect(parse('Step Up 3D (2010) 720p BluRay.mkv').is3d, isFalse);
      expect(parse('Vivarium (2019) 720p BluRay.mkv').is3d, isFalse);
    });
  });

  group('audio', () {
    test('dual, triple and multi audio', () {
      final expected = {
        'Vivarium (2019) 720p BluRay x264 ESub [Dual Audio]'
                '[Hindi 2.0+English 5.1] -mkvC.mkv':
            MultiAudio.dual,
        'The.Girl.Who.Played.With.Fire.2009.720p.BRRip.Dual.Audio.'
                'Swedish+English-YIFY.mkv':
            MultiAudio.dual,
        'Ong Bak (2003) [BRRip 720p] [Hindi-Eng-Thai] [Triple Audio] '
                'by []Omeg@king[].mkv':
            MultiAudio.triple,
        'The Witch Part 2 The Other One (2022) 1080p BluRay x265 HEVC ESub '
                '[Multi Audio][Hindi 2.0+English 5.1+Korean 5.1] -OlaM.mkv':
            MultiAudio.multi,
        'Stillwater (2018) 1080p WEBDL.mkv': null,
      };
      for (final MapEntry(key: name, value: audio) in expected.entries) {
        expect(parse(name).audio, audio, reason: name);
      }
    });

    test('languages, in the order written and once each', () {
      final expected = {
        'Vivarium (2019) 720p BluRay x264 ESub [Dual Audio]'
            '[Hindi 2.0+English 5.1] -mkvC.mkv': [
          'Hindi',
          'English',
        ],
        'Eye for an Eye 2 (2024) 720p BluRay x264 MSubs [Dual Audio]'
            '[Hindi 5.1+Chinese 5.1] -MsMod.mkv': [
          'Hindi',
          'Chinese',
        ],
        'Ong Bak (2003) [BRRip 720p] [Hindi-Eng-Thai] [Triple Audio] '
            'by []Omeg@king[].mkv': [
          'Hindi',
          'English',
          'Thai',
        ],
        'The.Girl.Who.Played.With.Fire.2009.720p.BRRip.Dual.Audio.'
            'Swedish+English-YIFY.mkv': [
          'Swedish',
          'English',
        ],
        'Chez.Nous.2017.FRENCH.720p.BRRip.1GB.MkvCage.mkv': ['French'],
        'Meri Khaki (2014) (Hindi Dubbed) 720p.mkv': ['Hindi'],
        'Movie (2019) Hindi 720p [Hindi+English].mkv': ['Hindi', 'English'],
        // In front of the year it is part of the title.
        'The English Patient (1996) 720p.mkv': <String>[],
      };
      for (final MapEntry(key: name, value: languages) in expected.entries) {
        expect(parse(name).languages, languages, reason: name);
      }
    });
  });

  group('release group', () {
    test('is the last word after the tags', () {
      final expected = {
        'Witness.Infection.2021.720p.WEBRip.800MB.x264-GalaxyRG.mkv':
            'GalaxyRG',
        'Vivarium (2019) 720p BluRay x264 ESub [Dual Audio]'
                '[Hindi 2.0+English 5.1] -mkvC.mkv':
            'mkvC',
        'Catch Me If You Can (2002) 720p BluRay x264 ESub [Dual Audio]'
                '[Hindi 2.0+English 5.1] - mkvC.mkv':
            'mkvC',
        'Pride.And.Prejudice.And.Zombies.2016.720p.BRRip.950MB.MkvCage.mkv':
            'MkvCage',
        'We.Need.to.Talk.About.Kevin.2011.720p.BrRip.x264.YIFY.mp4': 'YIFY',
        'Pearl in Paradise 2018 Hallmark 720p HDTV X264 Solar.mp4': 'Solar',
        'The Closed Circuit 2013 720p BluRay 850MB-Micromkv.mkv': 'Micromkv',
        '12 Rounds Reloaded (2013) 720p BRRip Nl subs DutchReleaseTeam.mkv':
            'DutchReleaseTeam',
        'Murder on the  Orient Express (1974) 720p BRrip x264 Junaid-Zia '
                '(PimpRG).mkv':
            'Junaid-Zia',
        'Ong Bak (2003) [BRRip 720p] [Hindi-Eng-Thai] [Triple Audio] '
                'by []Omeg@king[].mkv':
            'Omeg@king',
        'Movie.Name.2019.1080p.WEB-DL.DD5.1.H.264-GRP.mkv': 'GRP',
        'Movie (2019) 2160p UHD BluRay x265 HEVC 10bit HDR DTS-HD MA 5.1-GRP'
                '.mkv':
            'GRP',
      };
      for (final MapEntry(key: name, value: group) in expected.entries) {
        expect(parse(name).group, group, reason: name);
      }
    });

    test('site names lose their ending', () {
      final expected = {
        'Monstrum.2018.720p.BluRay.x264.950MB-Pahe.in.mkv': 'Pahe',
        'Black.Orpheus.1959.720p.BRRip.800MB.MkvCage.com.mkv': 'MkvCage',
        'The.Maus.2017.720p.NF.WEB-DL.MkvCage.WS.mkv': 'MkvCage',
        '2 Days in New York (2012) BluRay 720p 700MB Ganool.AG.mkv': 'Ganool',
        'Godzilla.Vs..Kong.2021.1080p.3D.BluRay.HSBS.x264-[YTS.MX].mp4': 'YTS',
      };
      for (final MapEntry(key: name, value: group) in expected.entries) {
        expect(parse(name).group, group, reason: name);
      }
    });

    test('is not made up when the name ends in a tag or a remark', () {
      for (final name in [
        'Stillwater (2018) 1080p WEBDL.mkv',
        'A Moment of Innocence (1996) Persian 480p DVDRip x264 ESub.mkv',
        'Konkurîto (2004) DVDRip [Concrete].avi',
        'Crisscross (2018) Bengali 720p WEB-DL x264 AAC { TaRa }.mkv',
        'Parbona Ami Charte Toke  [Bengali] Upscaled DVDRip - ESubs -1.49GB.mkv',
        'Zootopia (2016) 1080p [3D]',
        'Ooopss [from www.metacafe.com].mpg',
        // No tag at all: what follows the year is anyone's guess.
        'Bangla Eid Natok (2015) {Eid Ul Adha} Mofij BSC.mp4',
        'Facebook on Vodafone - Zoozoos poking each other.flv',
        'MacGruber (2010).avi',
      ]) {
        expect(parse(name).group, isNull, reason: name);
      }
    });
  });

  group('episodes', () {
    /// Title, season, episode and the words after the episode number.
    void expectEpisodes(Map<String, (String, int?, int?, String?)> expected) {
      for (final MapEntry(key: name, value: (title, season, episode, words))
          in expected.entries) {
        final parsed = parse(name);
        expect(parsed.title, title, reason: name);
        expect(parsed.season, season, reason: name);
        expect(parsed.episode, episode, reason: name);
        expect(parsed.episodeTitle, words, reason: name);
      }
    }

    test('S01E02', () {
      expectEpisodes({
        'The Bay (2019) S01E02 1080p WEBDL.mkv': ('The Bay', 1, 2, null),
        'Marvels Agents of S.H.I.E.L.D S06E02 1080p WEBRip.mkv': (
          'Marvels Agents of S.H.I.E.L.D',
          6,
          2,
          null,
        ),
        'The Widow S01E06_The Spider and the Web.mkv': (
          'The Widow',
          1,
          6,
          'The Spider and the Web',
        ),
        'Baywatch S10E18 Big Island Heat DVDRip.avi': (
          'Baywatch',
          10,
          18,
          'Big Island Heat',
        ),
        'Archer S03E07 Drift Problem.m4v': ('Archer', 3, 7, 'Drift Problem'),
        'Show.Name.S02E10.Episode.Name.720p.WEB.x264-GRP.mkv': (
          'Show Name',
          2,
          10,
          'Episode Name',
        ),
        '12 Monkeys S01E05.mkv': ('12 Monkeys', 1, 5, null),
        'show.s1e2.mkv': ('show', 1, 2, null),
        'Show S01 E02 720p.mkv': ('Show', 1, 2, null),
        'Show.S01.E02.Pilot.mkv': ('Show', 1, 2, 'Pilot'),
      });
    });

    test('keeps the year and the tags apart from the episode', () {
      final bay = parse('The Bay (2019) S01E02 1080p WEBDL.mkv');
      expect(bay.year, 2019);
      expect(bay.height, 1080);
      expect(bay.source, VideoSource.webDl);

      final web = parse(
        'Morichika S01E05 2021 720P[FreeDriveMovie.com]WEBDL h264.mp4',
      );
      expect(web.title, 'Morichika');
      expect(web.year, 2021);
      expect((web.season, web.episode), (1, 5));
      expect(web.episodeTitle, isNull);
      expect(web.height, 720);
      expect(web.group, isNull);
    });

    test('the words of an episode are not a release group', () {
      expect(parse('Archer S03E07 Drift Problem.m4v').group, isNull);
      expect(parse('Baywatch S10E18 Big Island Heat DVDRip.avi').group, isNull);
      expect(
        parse('Show.Name.S02E10.Episode.Name.720p.WEB.x264-GRP.mkv').group,
        'GRP',
      );
    });

    test('several episodes in one file', () {
      final expected = {
        'Show.S01E01-E03.720p.mkv': (1, 3),
        'Show S01E01E02.mkv': (1, 2),
        'Show.S01E01-03.mkv': (1, 3),
        'Show S01E05.mkv': (5, null),
        // Not a later episode, so not a range.
        'Show.S01E05-GRP.mkv': (5, null),
        'Show.S01E05-02.mkv': (5, null),
      };
      for (final MapEntry(key: name, value: (first, last))
          in expected.entries) {
        final parsed = parse(name);
        expect(parsed.episode, first, reason: name);
        expect(parsed.episodeEnd, last, reason: name);
      }
    });

    test('spelled out', () {
      expectEpisodes({
        'Grimm Season-03 Episode-17 Synchronicity.mp4': (
          'Grimm',
          3,
          17,
          'Synchronicity',
        ),
        'Bones Season-01 Episode-09 The Man In The Fallout Shelter.mkv': (
          'Bones',
          1,
          9,
          'The Man In The Fallout Shelter',
        ),
        'Neel Dorja Episode - 01.mkv': ('Neel Dorja', null, 1, null),
        'Nine And A Half Episode 2.MKV': ('Nine And A Half', null, 2, null),
        'Show EP05 720p.mkv': ('Show', null, 5, null),
        'Show Episode12.mkv': ('Show', null, 12, null),
        'Show E05.mkv': ('Show', null, 5, null),
      });
    });

    test('1x02', () {
      expectEpisodes({
        'Show 1x02 The Name.avi': ('Show', 1, 2, 'The Name'),
        // A film: the first word is never an episode number of this kind.
        '10x10 (2018) 720p BluRay x264 ESub [Dual Audio]'
            '[Hindi 2.0+English 5.1] -MsMod.mkv': (
          '10x10',
          null,
          null,
          null,
        ),
      });
    });

    test('a name that starts with the episode has no title', () {
      expectEpisodes({
        'S01E02.mkv': ('', 1, 2, null),
        'Episode 5.mkv': ('', null, 5, null),
        'E05 - Pilot.mkv': ('', null, 5, 'Pilot'),
        'Season 1': ('', 1, null, null),
        'S02': ('', 2, null, null),
      });
    });

    test('films with "Season" or "Episode" in the title', () {
      expectEpisodes({
        'Open Season 2 (2008) 720p BluRay.mkv': (
          'Open Season 2',
          null,
          null,
          null,
        ),
        'Open Season 3.mkv': ('Open Season 3', null, null, null),
        'Star Wars Episode 1 The Phantom Menace (1999) 720p.mkv': (
          'Star Wars Episode 1 The Phantom Menace',
          null,
          null,
          null,
        ),
        'Killing.Season.2013.720p.BluRay.x264.YIFY.mp4': (
          'Killing Season',
          null,
          null,
          null,
        ),
      });
    });

    test('season folders', () {
      final expected = {
        'The Bay (2019) Season 1 Complete': ('The Bay', 2019, 1),
        'Wu Assassins Season 01 (2019) Complete': ('Wu Assassins', 2019, 1),
        'Marvels Agents of S H I E L D Season 06 (2019) Completed': (
          'Marvels Agents of S H I E L D',
          2019,
          6,
        ),
        'Archer Season 3': ('Archer', null, 3),
        'Bones The Complete Season 2': ('Bones', null, 2),
        'Supernatural Season 10 Complete': ('Supernatural', null, 10),
        'Baywatch S10': ('Baywatch', null, 10),
        'The Strain S01 Season 1 Complete': ('The Strain', null, 1),
        'Sherwood (2019) S01 Completed': ('Sherwood', 2019, 1),
        'Neel Doorja Season 01 (2019)  Complete (EP01-EP06)': (
          'Neel Doorja',
          2019,
          1,
        ),
      };
      for (final MapEntry(key: name, value: (title, year, season))
          in expected.entries) {
        final parsed = parse(name);
        expect(parsed.title, title, reason: name);
        expect(parsed.year, year, reason: name);
        expect(parsed.season, season, reason: name);
        // "(EP01-EP06)" is what the folder holds.
        expect(parsed.episode, isNull, reason: name);
      }
      expect(
        parse(
          'Mushishi Season 01 (2005) (Japanese & English) Completed',
        ).languages,
        ['Japanese', 'English'],
      );
    });

    test('anime: numbered straight through after a dash', () {
      expectEpisodes({
        '[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv': (
          'Sousou no Frieren',
          null,
          5,
          null,
        ),
        '[Group] Show - 137 [720p].mkv': ('Show', null, 137, null),
        '[Group]_Show_Name_-_05v2_[720p].mkv': ('Show Name', null, 5, null),
        '[Group] Show - 5 [720p].mkv': ('Show', null, 5, null),
        '[Group] Show S2 - 05 [1080p].mkv': ('Show', 2, 5, null),
        'One Piece - 1071 [1080p].mkv': ('One Piece', null, 1071, null),
        'Naruto Shippuden - 137.mkv': ('Naruto Shippuden', null, 137, null),
      });
      final parsed = parse(
        '[SubsPlease] Sousou no Frieren - 05 (1080p) [ABCD1234].mkv',
      );
      expect(parsed.height, 1080);
      expect(parsed.group, 'SubsPlease');
    });

    test('a number after a dash is not always an episode', () {
      expectEpisodes({
        // One digit and no group in front.
        'Rocky - 2.mkv': ('Rocky - 2', null, null, null),
        // A year says it is a film.
        'Catch - 22 (1970) 720p.mkv': ('Catch - 22', null, null, null),
        // Words follow.
        'Movie - 10 Years Later.mkv': (
          'Movie - 10 Years Later',
          null,
          null,
          null,
        ),
        'The Twilight Saga-Breaking Dawn - Part 1 (2011) 720p BluRay.mkv': (
          'The Twilight Saga-Breaking Dawn - Part 1',
          null,
          null,
          null,
        ),
      });
      final year = parse('Movie - 2019.mkv');
      expect((year.title, year.year, year.episode), ('Movie', 2019, null));
    });
  });

  group('films in several files', () {
    test('CD and disc numbers', () {
      final expected = {
        'Koizora (2007) CD1.mp4': ('Koizora', 1),
        'Ashani Sanket AKA Distant Thunder-CD2(1973).avi': (
          'Ashani Sanket AKA Distant Thunder',
          2,
        ),
        'house.of.tolerance.2011.dvdrip.CD-1.avi': ('house of tolerance', 1),
        'Please Teach Me English (2003) DVDrip  DISC-1.avi': (
          'Please Teach Me English',
          1,
        ),
        'White.White.World.2010.DVDRip.XviD.CD1-REACTOR.avi': (
          'White White World',
          1,
        ),
        'Las.maletas.de.Tulse.Luper.Dual.CD1.avi': (
          'Las maletas de Tulse Luper Dual',
          1,
        ),
        '(1973) Ashani Sanket (Distant Thunder)-CD2': ('Ashani Sanket', 2),
        // "Part" belongs to the title.
        'The Witch Part 2 The Other One (2022) 1080p BluRay.mkv': (
          'The Witch Part 2 The Other One',
          null,
        ),
        'Vivarium (2019) 720p BluRay.mkv': ('Vivarium', null),
      };
      for (final MapEntry(key: name, value: (title, part))
          in expected.entries) {
        final parsed = parse(name);
        expect(parsed.title, title, reason: name);
        expect(parsed.part, part, reason: name);
      }
      expect(
        parse('Ashani Sanket AKA Distant Thunder-CD2(1973).avi').year,
        1973,
      );
      expect(
        parse('White.White.World.2010.DVDRip.XviD.CD1-REACTOR.avi').group,
        'REACTOR',
      );
      expect(parse('house.of.tolerance.2011.dvdrip.CD-1.avi').group, isNull);
    });
  });

  group('trailers and samples', () {
    test('are told apart from the film', () {
      final expected = {
        'Trailer - See No Evil 2 (2014).mp4': (
          'See No Evil 2',
          2014,
          ExtraKind.trailer,
        ),
        'Trailer #2 Need for Speed (2014).mp4': (
          'Need for Speed',
          2014,
          ExtraKind.trailer,
        ),
        'Trailer - Trip to Italy.mp4': (
          'Trip to Italy',
          null,
          ExtraKind.trailer,
        ),
        'United 93 (2006) Trailer.mp4': ('United 93', 2006, ExtraKind.trailer),
        'Man of Steel (2013) Official Trailer 3.mp4': (
          'Man of Steel',
          2013,
          ExtraKind.trailer,
        ),
        'HALKa Trailer.mkv': ('HALKa', null, ExtraKind.trailer),
        'Don 2 - Theatrical Trailer [Funmaza.com].mp4': (
          'Don 2',
          null,
          ExtraKind.trailer,
        ),
        'Movie Official Trailer 2 (2019).mp4': (
          'Movie',
          2019,
          ExtraKind.trailer,
        ),
        'Sample Vikingdom 2013.mp4': ('Vikingdom', 2013, ExtraKind.sample),
        'sample.mkv': ('sample', null, ExtraKind.sample),
        'Movie.2019.720p.BluRay.x264-GRP.sample.mkv': (
          'Movie',
          2019,
          ExtraKind.sample,
        ),
        // Films.
        'Trailer Park Boys (2006) 720p.mkv': ('Trailer Park Boys', 2006, null),
        'Trailer.mkv': ('Trailer', null, null),
        'Vivarium (2019) 720p BluRay.mkv': ('Vivarium', 2019, null),
      };
      for (final MapEntry(key: name, value: (title, year, extra))
          in expected.entries) {
        final parsed = parse(name);
        expect(parsed.title, title, reason: name);
        expect(parsed.year, year, reason: name);
        expect(parsed.extra, extra, reason: name);
      }
    });
  });

  test('reads every part of one full name', () {
    final parsed = parse(
      'Hellboy The Crooked Man (2024) 720p AMZN-WEB x264 ESub [Dual Audio]'
      '[Hindi 2.0+English 5.1] -mkvC.mkv',
    );
    expect(parsed.title, 'Hellboy The Crooked Man');
    expect(parsed.year, 2024);
    expect(parsed.height, 720);
    expect(parsed.source, VideoSource.webDl);
    expect(parsed.codec, VideoCodec.h264);
    expect(parsed.audio, MultiAudio.dual);
    expect(parsed.languages, ['Hindi', 'English']);
    expect(parsed.is3d, isFalse);
    expect(parsed.group, 'mkvC');
  });

  test('the newest year allowed is next year by default', () {
    final next = DateTime.now().year + 1;
    expect(parseReleaseName('Movie ($next) 720p.mkv').year, next);
    expect(parseReleaseName('Movie (${next + 1}) 720p.mkv').year, isNull);
    expect(parse('Movie (1899) 720p.mkv').year, isNull);
  });

  test('never throws, whatever the name', () {
    for (final name in [
      '',
      ' ',
      '.',
      '...',
      '.mkv',
      '-',
      '---+++',
      '[',
      ']',
      '[]',
      '(',
      '()',
      '(((',
      ')))',
      '{[(',
      '[unclosed 720p',
      '(2019',
      '2019',
      '720p',
      '720p.mkv',
      '[720p]',
      '(2019) [1080p]',
      '-x264-',
      'a' * 5000,
      '${'[x]' * 500}.mkv',
      '${'a.' * 2000}mkv',
      '\u200E\u202E',
      '😀 (2019) 720p.mkv',
    ]) {
      expect(() => parse(name), returnsNormally, reason: name);
      expect(parse(name).title, isNotNull, reason: name);
    }
  });

  test('is quick enough for a whole library', () {
    const names = [
      'Witness.Infection.2021.720p.WEBRip.800MB.x264-GalaxyRG.mkv',
      'Vivarium (2019) 720p BluRay x264 ESub [Dual Audio]'
          '[Hindi 2.0+English 5.1] -mkvC.mkv',
      'The Bay (2019) S01E02 1080p WEBDL.mkv',
      'necklace.mkv',
    ];
    final watch = Stopwatch()..start();
    for (var i = 0; i < 100000; i++) {
      parseReleaseName(names[i % names.length], latestYear: 2027);
    }
    // About a second on a slow machine; the limit only catches a blow-up.
    expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
  });
}
