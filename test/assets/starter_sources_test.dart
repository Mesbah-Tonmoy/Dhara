// Guards the source lists shipped with the app. The app's own parser does
// the general checks; on top of that the files must be tidy (see
// assets/sources/README.md), so a careless hand edit fails here first.
import 'dart:convert';
import 'dart:io';

import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_list.dart';
import 'package:dhara/features/sources/starter_sources.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _fields = {
  'id',
  'name',
  'provider',
  'isp',
  'type',
  'category',
  'baseUrls',
  'portalUrl',
  'notes',
};

/// Hosts that are not BDIX servers, whatever a public list says: social
/// networks, site builders, paste and code hosts.
const _notServers = [
  'facebook.com',
  'google.com',
  'youtube.com',
  'pastebin.com',
  'github.io',
  'wixsite.com',
  'webs.com',
  'blogspot.com',
  'wordpress.com',
];

void main() {
  final starterText = File(starterSourcesAsset).readAsStringSync();
  final candidateText = File(candidateSourcesAsset).readAsStringSync();
  List<Map<String, dynamic>> raw(String text) =>
      ((jsonDecode(text) as Map<String, dynamic>)['sources'] as List)
          .cast<Map<String, dynamic>>();
  final files = {
    starterSourcesAsset: starterText,
    candidateSourcesAsset: candidateText,
  };

  test('the app loads both lists from its asset bundle, the starter list '
      'first', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final sources = await loadStarterSources(rootBundle);

    final starter = parseSourceList(starterText);
    final candidates = parseSourceList(candidateText);
    expect(sources.take(starter.length), starter);
    // Nothing of either file is dropped: they do not overlap (see below).
    expect(sources.skip(starter.length), candidates);
    expect(candidates, isNotEmpty);
  });

  test('the starter list has the version-1 envelope', () {
    final root = jsonDecode(starterText) as Map<String, dynamic>;
    expect(root['schemaVersion'], sourceListSchemaVersion);
    expect(root['checkedOn'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  test('the candidates say when and where they were taken from', () {
    final root = jsonDecode(candidateText) as Map<String, dynamic>;
    expect(root['schemaVersion'], sourceListSchemaVersion);
    expect(root['takenOn'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(Uri.parse(root['takenFrom'] as String).scheme, 'https');
  });

  for (final MapEntry(key: file, value: text) in files.entries) {
    group(file, () {
      test('every source has exactly the documented fields', () {
        for (final source in raw(text)) {
          expect(source.keys.toSet(), _fields, reason: '${source['id']}');
        }
      });

      test('is already in the form the parser would turn it into', () {
        final parsed = [
          for (final source in parseSourceList(text)) source.toJson(),
        ];

        expect(parsed, raw(text));
      });
    });
  }

  test('no id and no base URL is listed twice, in either file or across '
      'them', () {
    final ids = <String>{};
    final urls = <String>{};
    for (final text in files.values) {
      for (final source in raw(text)) {
        expect(ids.add(source['id'] as String), isTrue, reason: 'id');
        for (final url in source['baseUrls'] as List) {
          expect(urls.add(url as String), isTrue, reason: 'duplicate $url');
        }
      }
    }
  });

  group('the candidates', () {
    final starter = parseSourceList(starterText);
    final candidates = parseSourceList(candidateText);

    test('name no server the starter list already reads or names as a '
        'front page', () {
      String bare(Uri url) => url.authority.replaceFirst(RegExp('^www\\.'), '');
      final known = {
        for (final source in starter) ...[
          for (final url in source.baseUrls) bare(url),
          if (source.portalUrl case final portal?) bare(portal),
        ],
      };

      for (final source in candidates) {
        for (final url in source.baseUrls) {
          expect(known, isNot(contains(bare(url))), reason: source.id);
        }
      }
    });

    test('are one server each, of a type the test has yet to find', () {
      for (final source in candidates) {
        expect(source.id, startsWith('bdix-'));
        expect(source.type, SourceType.customSite, reason: source.id);
        expect(
          {for (final url in source.baseUrls) url.authority},
          hasLength(1),
          reason: source.id,
        );
      }
    });

    test('hold no social network, site builder or home-network address', () {
      for (final source in candidates) {
        final host = source.baseUrls.first.host;
        for (final other in _notServers) {
          expect(
            host == other || host.endsWith('.$other'),
            isFalse,
            reason: source.id,
          );
        }
        expect(
          RegExp(r'^(192\.168\.|127\.|169\.254\.)').hasMatch(host),
          isFalse,
          reason: source.id,
        );
      }
    });
  });

  group('mergeStarterSources', () {
    Source source(String id, String url) => Source(
      id: id,
      name: id,
      type: SourceType.customSite,
      category: SourceCategory.mixed,
      baseUrls: [Uri.parse(url)],
    );

    test('leaves out a candidate whose id or server the starter list has', () {
      final starter = [source('a', 'http://10.0.0.1/films/')];
      final fresh = source('d', 'http://10.0.0.1:8096/');

      expect(
        mergeStarterSources(starter, [
          source('a', 'http://10.0.0.9/'),
          source('b', 'http://10.0.0.1/'),
          fresh,
        ]),
        [...starter, fresh],
      );
    });
  });
}
