// Guards the shape of the starter source list, so a hand edit that breaks
// the documented schema (assets/sources/README.md) fails here first.
import 'dart:convert';
import 'dart:io';

import 'package:dhara/core/net/media_url.dart';
import 'package:flutter_test/flutter_test.dart';

const _types = {
  'directory_listing',
  'h5ai',
  'emby',
  'jellyfin',
  'custom_site',
};
const _categories = {'movies', 'series', 'anime', 'mixed'};
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

void main() {
  final root = jsonDecode(
    File('assets/sources/starter_sources.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final sources = (root['sources'] as List).cast<Map<String, dynamic>>();

  test('is declared as an asset', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('- assets/sources/starter_sources.json'),
    );
  });

  test('has the version-1 envelope', () {
    expect(root['schemaVersion'], 1);
    expect(root['checkedOn'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(sources, isNotEmpty);
  });

  test('every source has exactly the documented fields', () {
    for (final source in sources) {
      expect(source.keys.toSet(), _fields, reason: '${source['id']}');
    }
  });

  test('ids are unique and URL-friendly', () {
    final ids = sources.map((s) => s['id'] as String).toList();

    expect(ids.toSet(), hasLength(ids.length));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')));
    }
  });

  test('names, types and categories are valid', () {
    for (final source in sources) {
      final id = source['id'];
      expect((source['name'] as String).trim(), isNotEmpty, reason: '$id');
      expect(_types, contains(source['type']), reason: '$id');
      expect(_categories, contains(source['category']), reason: '$id');
      for (final optional in ['provider', 'isp', 'notes']) {
        expect(source[optional], anyOf(isNull, isA<String>()), reason: '$id');
      }
    }
  });

  test('every base URL is a plain http(s) folder URL, listed only once', () {
    final seen = <String>{};
    for (final source in sources) {
      final id = source['id'];
      final urls = (source['baseUrls'] as List).cast<String>();
      expect(urls, isNotEmpty, reason: '$id');
      for (final url in urls) {
        final parsed = parseMediaUrl(url);
        expect(parsed, isNotNull, reason: '$id: $url');
        expect(parsed.toString(), url, reason: '$id: not normalised');
        expect(url, endsWith('/'), reason: '$id: $url');
        expect(parsed!.hasQuery || parsed.hasFragment, isFalse, reason: url);
        expect(parsed.userInfo, isEmpty, reason: '$id: no credentials');
        expect(seen.add(url), isTrue, reason: 'duplicate $url');
      }
    }
  });

  test('portal URLs, where given, are http(s) too', () {
    for (final source in sources) {
      final portal = source['portalUrl'];
      if (portal == null) continue;
      expect(parseMediaUrl(portal as String), isNotNull, reason: portal);
    }
  });
}
