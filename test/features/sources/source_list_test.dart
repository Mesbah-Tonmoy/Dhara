import 'dart:convert';

import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_list.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _source([Map<String, Object?> changes = const {}]) => {
      'id': 'dhakaflix-7',
      'name': 'DhakaFlix 7',
      'provider': 'DhakaFlix',
      'isp': 'SAM Online',
      'type': 'h5ai',
      'category': 'movies',
      'baseUrls': ['http://172.16.50.7/DHAKA-FLIX-7/'],
      'portalUrl': 'http://172.16.50.4/',
      'notes': 'English movies',
      ...changes,
    };

String _list(List<Object?> sources, {Object? version = 1}) =>
    jsonEncode({'schemaVersion': version, 'sources': sources});

/// The rejection message for a list holding one source with [changes].
String _rejection(Map<String, Object?> changes) =>
    _listRejection(_list([_source(changes)]));

String _listRejection(String text) {
  try {
    parseSourceList(text);
  } on SourceFormatException catch (error) {
    return error.message;
  }
  fail('The list was accepted');
}

void main() {
  group('parseSourceList', () {
    test('reads every field of a source', () {
      final source = parseSourceList(_list([_source()])).single;

      expect(source.id, 'dhakaflix-7');
      expect(source.name, 'DhakaFlix 7');
      expect(source.provider, 'DhakaFlix');
      expect(source.isp, 'SAM Online');
      expect(source.type, SourceType.h5ai);
      expect(source.category, SourceCategory.movies);
      expect(source.baseUrls, [Uri.parse('http://172.16.50.7/DHAKA-FLIX-7/')]);
      expect(source.portalUrl, Uri.parse('http://172.16.50.4/'));
      expect(source.notes, 'English movies');
    });

    test('knows every type and category name', () {
      for (final type in SourceType.values) {
        for (final category in SourceCategory.values) {
          final source = parseSourceList(
            _list([
              _source({'type': type.jsonName, 'category': category.name}),
            ]),
          ).single;

          expect(source.type, type);
          expect(source.category, category);
        }
      }
    });

    test('optional fields may be null, blank or left out', () {
      final json = _source({'provider': null, 'isp': '  ', 'notes': null})
        ..remove('portalUrl');

      final source = parseSourceList(_list([json])).single;

      expect(source.provider, isNull);
      expect(source.isp, isNull);
      expect(source.portalUrl, isNull);
      expect(source.notes, isNull);
    });

    test('trims text and keeps line breaks in notes', () {
      final source = parseSourceList(
        _list([
          _source({'name': '  DhakaFlix 7 ', 'notes': 'line 1\nline 2'}),
        ]),
      ).single;

      expect(source.name, 'DhakaFlix 7');
      expect(source.notes, 'line 1\nline 2');
    });

    test('makes base URLs end in "/" and drops repeats', () {
      final source = parseSourceList(
        _list([
          _source({
            'baseUrls': [
              'http://10.16.100.202/ftps10',
              'http://10.16.100.202/ftps10/',
              'http://example.net',
            ],
          }),
        ]),
      ).single;

      expect(source.baseUrls.map((url) => url.toString()), [
        'http://10.16.100.202/ftps10/',
        'http://example.net/',
      ]);
    });

    test('ignores keys it does not know', () {
      final text = jsonEncode({
        'schemaVersion': 1,
        'checkedOn': '2026-11-12',
        'sources': [
          _source({'addedLater': true}),
        ],
      });

      expect(parseSourceList(text), hasLength(1));
    });

    test('accepts an empty list', () {
      expect(parseSourceList(_list([])), isEmpty);
    });

    test('rejects text that is not a JSON object', () {
      expect(_listRejection('{"schemaVersion": 1,'), contains('not valid JSON'));
      expect(_listRejection('[]'), contains('JSON object'));
      expect(
        _listRejection(' ' * (maxSourceListLength + 1)),
        contains('too large'),
      );
    });

    test('rejects a missing, odd or newer schema version', () {
      expect(_listRejection('{"sources": []}'), contains('schemaVersion'));
      expect(_listRejection(_list([], version: '1')), contains('schemaVersion'));
      expect(_listRejection(_list([], version: 0)), contains('schemaVersion'));
      expect(_listRejection(_list([], version: 2)), contains('version 2'));
    });

    test('rejects a "sources" value that is not a list, or is too long', () {
      expect(_listRejection('{"schemaVersion": 1}'), contains('"sources"'));
      expect(
        _listRejection(_list(List.filled(maxSources + 1, _source()))),
        contains('more than $maxSources'),
      );
    });

    test('rejects two sources with the same id', () {
      expect(
        _listRejection(_list([_source(), _source()])),
        startsWith('sources[1].id'),
      );
    });

    test('names the entry and field that is wrong', () {
      expect(
        _listRejection(_list([_source(), 'not an object'])),
        startsWith('sources[1]:'),
      );
      expect(
        _listRejection(
          _list([
            _source(),
            _source({'id': 'second', 'type': 'ftp'}),
          ]),
        ),
        startsWith('sources[1].type:'),
      );
    });

    test('rejects bad ids', () {
      for (final id in [null, '', 'DhakaFlix', 'dhaka flix', '-a', 'a--b', 7]) {
        expect(_rejection({'id': id}), startsWith('sources[0].id'));
      }
      expect(_rejection({'id': 'a' * 65}), startsWith('sources[0].id'));
    });

    test('rejects bad text fields', () {
      expect(_rejection({'name': null}), startsWith('sources[0].name'));
      expect(_rejection({'name': '   '}), startsWith('sources[0].name'));
      expect(_rejection({'name': 'a' * 81}), startsWith('sources[0].name'));
      expect(_rejection({'name': 'a\nb'}), contains('control characters'));
      expect(_rejection({'provider': 5}), startsWith('sources[0].provider'));
      expect(_rejection({'notes': 'a\u0000b'}), contains('control characters'));
      expect(_rejection({'notes': 'a' * 1001}), startsWith('sources[0].notes'));
    });

    test('rejects unknown types and categories', () {
      expect(_rejection({'type': 'ftp'}), contains('directory_listing, h5ai'));
      expect(_rejection({'type': null}), startsWith('sources[0].type'));
      expect(_rejection({'category': 'games'}), contains('movies, series'));
    });

    test('rejects a source without base URLs, or with too many', () {
      expect(_rejection({'baseUrls': null}), startsWith('sources[0].baseUrls'));
      expect(_rejection({'baseUrls': <String>[]}), contains('at least one'));
      expect(
        _rejection({
          'baseUrls': [
            for (var i = 0; i <= maxBaseUrlsPerSource; i++) 'http://h/$i/',
          ],
        }),
        contains('more than $maxBaseUrlsPerSource'),
      );
    });

    test('only accepts plain http(s) base URLs', () {
      for (final url in [
        'file:///C:/Windows/',
        'ftp://ftp.example.net/',
        'smb://server/share/',
        '/relative/path/',
        'http:///no-host/',
        '',
        42,
        'http://h/${'a' * 2048}/',
      ]) {
        expect(
          _rejection({
            'baseUrls': [url],
          }),
          'sources[0].baseUrls[0]: must be an http or https URL.',
          reason: '$url',
        );
      }
    });

    test('rejects credentials, queries and fragments in base URLs', () {
      String rejectionFor(String url) => _rejection({
            'baseUrls': [url],
          });

      expect(rejectionFor('http://me:secret@h/'), contains('password'));
      expect(rejectionFor('http://h/?dir=movies'), contains('"?" or "#"'));
      expect(rejectionFor('http://h/#movies'), contains('"?" or "#"'));
    });

    test('never repeats rejected text in the message', () {
      expect(
        _rejection({
          'baseUrls': ['http://me:secret@h/'],
        }),
        isNot(contains('secret')),
      );
      expect(_rejection({'type': 'evil-type'}), isNot(contains('evil')));
    });

    test('allows private addresses and https', () {
      final source = parseSourceList(
        _list([
          _source({
            'baseUrls': ['http://10.1.1.1/', 'https://172.16.50.4:8443/a/'],
          }),
        ]),
      ).single;

      expect(source.baseUrls, hasLength(2));
    });

    test('checks the portal URL, but lets it have a query', () {
      expect(
        _rejection({'portalUrl': 'javascript:alert(1)'}),
        startsWith('sources[0].portalUrl'),
      );
      expect(_rejection({'portalUrl': 'http://a:b@h/'}), contains('password'));
      expect(
        parseSourceList(
          _list([
            _source({'portalUrl': 'http://h/index.php?page=home'}),
          ]),
        ).single.portalUrl,
        Uri.parse('http://h/index.php?page=home'),
      );
    });
  });

  group('writing', () {
    test('a list survives being written and read again', () {
      final sources = parseSourceList(
        _list([
          _source(),
          _source({
            'id': 'second',
            'provider': null,
            'isp': null,
            'type': 'directory_listing',
            'category': 'mixed',
            'baseUrls': ['http://10.16.100.241/ftps3d1/', 'http://h/b/'],
            'portalUrl': null,
            'notes': null,
          }),
        ]),
      );

      final written = jsonEncode(sourcesToJson(sources));

      expect(parseSourceList(written), sources);
    });

    test('a source is written with exactly the documented fields', () {
      final json = parseSourceList(_list([_source()])).single.toJson();

      expect(json, _source());
    });
  });

  group('Source', () {
    test('equal content means equal sources', () {
      Source read([Map<String, Object?> changes = const {}]) =>
          sourceFromJson(_source(changes));

      expect(read(), read());
      expect(read().hashCode, read().hashCode);
      expect(read(), isNot(read({'name': 'Other'})));
      expect(
        read(),
        isNot(
          read({
            'baseUrls': ['http://h/'],
          }),
        ),
      );
    });

    test('a source built in code can be checked with sourceFromJson', () {
      final good = Source(
        id: 'mine',
        name: 'My server',
        type: SourceType.directoryListing,
        category: SourceCategory.mixed,
        baseUrls: [Uri.parse('http://10.0.0.5/media')],
      );
      final bad = Source(
        id: 'Not An Id',
        name: 'My server',
        type: SourceType.directoryListing,
        category: SourceCategory.mixed,
        baseUrls: [Uri.parse('http://10.0.0.5/media/')],
      );

      expect(
        sourceFromJson(good.toJson()).baseUrls.single.toString(),
        'http://10.0.0.5/media/',
      );
      expect(
        () => sourceFromJson(bad.toJson()),
        throwsA(isA<SourceFormatException>()),
      );
    });
  });
}
