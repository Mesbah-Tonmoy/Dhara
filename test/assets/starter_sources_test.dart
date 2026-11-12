// Guards the starter source list. The app's own parser does the general
// checks; on top of that the shipped file must be tidy (see
// assets/sources/README.md), so a careless hand edit fails here first.
import 'dart:convert';
import 'dart:io';

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

void main() {
  final text = File(starterSourcesAsset).readAsStringSync();
  final root = jsonDecode(text) as Map<String, dynamic>;
  final rawSources = (root['sources'] as List).cast<Map<String, dynamic>>();

  test('the app loads it from its asset bundle', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final sources = await loadStarterSources(rootBundle);

    expect(sources, parseSourceList(text));
    expect(sources, isNotEmpty);
  });

  test('has the version-1 envelope', () {
    expect(root['schemaVersion'], sourceListSchemaVersion);
    expect(root['checkedOn'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  test('every source has exactly the documented fields', () {
    for (final source in rawSources) {
      expect(source.keys.toSet(), _fields, reason: '${source['id']}');
    }
  });

  test('is already in the form the parser would turn it into', () {
    final parsed = [
      for (final source in parseSourceList(text)) source.toJson(),
    ];

    expect(parsed, rawSources);
  });

  test('lists every base URL only once', () {
    final seen = <String>{};
    for (final source in rawSources) {
      for (final url in source['baseUrls'] as List) {
        expect(seen.add(url as String), isTrue, reason: 'duplicate $url');
      }
    }
  });
}
