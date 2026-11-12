import 'dart:convert';
import 'dart:io';

import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_list.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter_test/flutter_test.dart';

Source _source(String id, {String? name, String url = 'http://10.0.0.1/'}) =>
    Source(
      id: id,
      name: name ?? 'Server $id',
      type: SourceType.h5ai,
      category: SourceCategory.mixed,
      baseUrls: [Uri.parse('$url$id/')],
    );

final _starter = [_source('alpha'), _source('beta'), _source('gamma')];

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dhara_sources_test_');
    file = File('${dir.path}/nested/sources.json');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// A store as the app would have after starting up.
  Future<SourceStore> open({List<Source>? starter}) async {
    final store = SourceStore(starter: starter ?? _starter, file: file);
    await store.load();
    return store;
  }

  List<String> ids(SourceStore store) =>
      [for (final source in store.sources) source.id];

  Map<String, dynamic> saved() =>
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  test('starts as the starter list with nothing enabled', () async {
    final store = await open();

    expect(store.sources, _starter);
    expect(store.sources.where((s) => store.isEnabled(s.id)), isEmpty);
    expect(store.savedFileWasUnreadable, isFalse);
    expect(file.existsSync(), isFalse, reason: 'loading writes nothing');
  });

  test('without a file, changes last for this run only', () async {
    final store = SourceStore(starter: _starter);
    await store.load();

    await store.add(_source('mine'));
    await store.setEnabled(['alpha'], enabled: true);
    await store.remove('beta');

    expect(ids(store), ['alpha', 'gamma', 'mine']);
    expect(store.isEnabled('alpha'), isTrue);
    expect(store.savedFileWasUnreadable, isFalse);
    expect(dir.listSync(), isEmpty);
  });

  test('knows the starter list even before load', () {
    expect(SourceStore(starter: _starter, file: file).sources, _starter);
  });

  test('remembers which sources are enabled', () async {
    final store = await open();

    await store.setEnabled(['alpha', 'gamma', 'unknown'], enabled: true);
    await store.setEnabled(['gamma'], enabled: false);

    final reopened = await open();
    expect(reopened.isEnabled('alpha'), isTrue);
    expect(reopened.isEnabled('beta'), isFalse);
    expect(reopened.isEnabled('gamma'), isFalse);
    expect(reopened.isEnabled('unknown'), isFalse);
  });

  test('does not write when enabling changes nothing', () async {
    final store = await open();

    await store.setEnabled(['alpha'], enabled: false);
    await store.setEnabled(['unknown'], enabled: true);

    expect(file.existsSync(), isFalse);
  });

  test('adds a source after the starter ones and keeps it', () async {
    final store = await open();

    await store.add(_source('mine'));

    expect(ids(store), ['alpha', 'beta', 'gamma', 'mine']);
    expect(store.isEnabled('mine'), isFalse);
    final reopened = await open();
    expect(reopened.sources.last, _source('mine'));
  });

  test('refuses to add an id that is taken or a source that is not valid',
      () async {
    final store = await open();
    final invalid = Source(
      id: 'Not An Id',
      name: 'x',
      type: SourceType.h5ai,
      category: SourceCategory.mixed,
      baseUrls: [Uri.parse('http://10.0.0.1/')],
    );

    await expectLater(
      store.add(_source('alpha', name: 'Impostor')),
      throwsA(isA<SourceFormatException>()),
    );
    await expectLater(
      store.add(invalid),
      throwsA(isA<SourceFormatException>()),
    );

    expect(store.sources, _starter);
    expect(file.existsSync(), isFalse);
  });

  test('stores sources in their checked form', () async {
    final store = await open();

    await store.add(
      Source(
        id: 'mine',
        name: 'Mine',
        type: SourceType.directoryListing,
        category: SourceCategory.movies,
        baseUrls: [Uri.parse('http://10.0.0.9/movies')],
      ),
    );

    expect(
      store.sources.last.baseUrls.single.toString(),
      'http://10.0.0.9/movies/',
    );
  });

  test('keeps an edited starter source in its place', () async {
    final store = await open();
    final edited = _source('beta', name: 'Beta (renamed)');

    await store.update(edited);

    expect(ids(store), ['alpha', 'beta', 'gamma']);
    final reopened = await open();
    expect(reopened.sources[1], edited);
  });

  test('editing a source back to the starter values saves no change', () async {
    final store = await open();

    await store.update(_source('beta', name: 'Beta (renamed)'));
    await store.update(_source('beta'));

    expect(store.sources, _starter);
    expect(saved()['sources'], isEmpty);
  });

  test('updates an added source, and refuses an unknown id', () async {
    final store = await open();
    await store.add(_source('mine'));

    await store.update(_source('mine', name: 'Mine v2'));
    await expectLater(
      store.update(_source('nobody')),
      throwsA(isA<SourceFormatException>()),
    );

    final reopened = await open();
    expect(reopened.sources.last.name, 'Mine v2');
    expect(ids(reopened), ['alpha', 'beta', 'gamma', 'mine']);
  });

  test('removes starter and added sources for good', () async {
    final store = await open();
    await store.add(_source('mine'));
    await store.setEnabled(['beta', 'mine'], enabled: true);

    await store.remove('beta');
    await store.remove('mine');
    await store.remove('unknown');

    expect(ids(store), ['alpha', 'gamma']);
    expect(store.isEnabled('beta'), isFalse);
    final reopened = await open();
    expect(ids(reopened), ['alpha', 'gamma']);
    expect(saved()['enabledIds'], isEmpty);
  });

  test('a removed starter source can be added again', () async {
    final store = await open();
    await store.update(_source('beta', name: 'Beta (renamed)'));
    await store.remove('beta');

    await store.add(_source('beta'));

    final reopened = await open();
    expect(reopened.sources, _starter);
    expect(saved()['removedIds'], isEmpty);
    expect(saved()['sources'], isEmpty);
  });

  test('saves only the changes, in the documented list format', () async {
    final store = await open();
    await store.add(_source('mine'));
    await store.remove('alpha');
    await store.setEnabled(['gamma'], enabled: true);

    expect(saved(), {
      'schemaVersion': sourceListSchemaVersion,
      'sources': [_source('mine').toJson()],
      'removedIds': ['alpha'],
      'enabledIds': ['gamma'],
      'health': <String, Object?>{},
    });
    expect(dir.listSync(recursive: true).whereType<File>(), hasLength(1));
  });

  test('follows the starter list when it changes between versions', () async {
    final store = await open();
    await store.update(_source('beta', name: 'My beta'));
    await store.remove('gamma');
    await store.setEnabled(['alpha', 'beta'], enabled: true);

    final newStarter = [
      _source('alpha', name: 'Alpha, new address', url: 'http://10.9.9.9/'),
      _source('beta'),
      _source('delta'),
    ];
    final reopened = await open(starter: newStarter);

    expect(ids(reopened), ['alpha', 'beta', 'delta']);
    expect(reopened.sources[0].name, 'Alpha, new address');
    expect(reopened.sources[1].name, 'My beta', reason: 'user edits win');
    expect(reopened.isEnabled('alpha'), isTrue);
    expect(reopened.isEnabled('delta'), isFalse);
  });

  test('an edited source that left the starter list stays as a user source',
      () async {
    final store = await open();
    await store.update(_source('beta', name: 'My beta'));

    final reopened = await open(starter: [_source('alpha')]);

    expect(ids(reopened), ['alpha', 'beta']);
    expect(reopened.sources.last.name, 'My beta');
  });

  test('tells listeners about every change', () async {
    final store = await open();
    var calls = 0;
    store.addListener(() => calls++);

    await store.add(_source('mine'));
    await store.update(_source('mine', name: 'Mine v2'));
    await store.setEnabled(['mine'], enabled: true);
    await store.setEnabled(['mine'], enabled: true);
    await store.remove('mine');
    await store.load();

    expect(calls, 5);
  });

  test('changes made without waiting are all saved, in order', () async {
    final store = await open();

    final writes = [
      store.add(_source('one')),
      store.add(_source('two')),
      store.setEnabled(['one', 'two', 'alpha'], enabled: true),
      store.remove('one'),
    ];
    await Future.wait(writes);

    final reopened = await open();
    expect(ids(reopened), ['alpha', 'beta', 'gamma', 'two']);
    expect(reopened.isEnabled('two'), isTrue);
    expect(reopened.isEnabled('alpha'), isTrue);
  });

  group('a damaged saved file', () {
    Future<void> expectSetAside(String content) async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);

      final store = await open();

      expect(store.sources, _starter);
      expect(store.savedFileWasUnreadable, isTrue);
      expect(file.existsSync(), isFalse);
      expect(File('${file.path}.bad').readAsStringSync(), content);

      // The store keeps working, and the next start is clean again.
      await store.setEnabled(['alpha'], enabled: true);
      final reopened = await open();
      expect(reopened.isEnabled('alpha'), isTrue);
      expect(reopened.savedFileWasUnreadable, isFalse);
    }

    test('that is not JSON is set aside', () async {
      await expectSetAside('{"schemaVersion": 1, "sources": [');
    });

    test('with a bad source is set aside as a whole', () async {
      await expectSetAside(
        jsonEncode({
          'schemaVersion': 1,
          'sources': [
            _source('mine').toJson(),
            {'id': 'broken'},
          ],
          'enabledIds': ['alpha'],
        }),
      );
    });

    test('with a bad id list is set aside', () async {
      await expectSetAside(
        jsonEncode({
          'schemaVersion': 1,
          'sources': <Object>[],
          'enabledIds': 'alpha',
        }),
      );
    });

    test('from a newer app version is set aside, not overwritten', () async {
      await expectSetAside(
        jsonEncode({'schemaVersion': 2, 'sources': <Object>[]}),
      );
    });

    test('that is not UTF-8 text is set aside', () async {
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync([0xFF, 0xFE, 0xFD]);

      final store = await open();

      expect(store.sources, _starter);
      expect(store.savedFileWasUnreadable, isTrue);
      expect(File('${file.path}.bad').existsSync(), isTrue);
    });
  });

  test('ignores saved ids that no longer exist', () async {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'sources': <Object>[],
        'removedIds': ['beta', 'long-gone'],
        'enabledIds': ['alpha', 'beta', 'long-gone'],
      }),
    );

    final store = await open();
    await store.setEnabled(['gamma'], enabled: true);

    expect(ids(store), ['alpha', 'gamma']);
    expect(saved()['removedIds'], ['beta']);
    expect(saved()['enabledIds'], ['alpha', 'gamma']);
  });

  group('test results', () {
    final checked = SourceHealth(
      checkedAt: DateTime(2026, 11, 12, 21, 30),
      reachable: true,
      readable: true,
      ping: const Duration(milliseconds: 14),
    );
    final dead = SourceHealth(
      checkedAt: DateTime(2026, 11, 12, 21, 31),
      reachable: false,
      readable: false,
    );

    test('are remembered across restarts', () async {
      final store = await open();
      expect(store.healthOf('alpha'), isNull);

      await store
          .recordHealth({'alpha': checked, 'beta': dead, 'nobody': dead});

      final reopened = await open();
      final alpha = reopened.healthOf('alpha')!;
      expect(alpha.checkedAt, checked.checkedAt);
      expect(alpha.readable, isTrue);
      expect(alpha.ping, const Duration(milliseconds: 14));
      expect(reopened.healthOf('beta')!.reachable, isFalse);
      expect(reopened.healthOf('beta')!.ping, isNull);
      expect(reopened.healthOf('gamma'), isNull);
      expect(reopened.healthOf('nobody'), isNull);
    });

    test('are dropped when the source changes or goes', () async {
      final store = await open();
      await store.add(_source('mine'));
      await store
          .recordHealth({'alpha': checked, 'beta': checked, 'mine': checked});

      await store.update(_source('alpha', name: 'Alpha, moved'));
      await store.update(_source('beta'));
      await store.remove('mine');
      await store.add(_source('mine'));

      expect(store.healthOf('alpha'), isNull, reason: 'edited');
      expect(store.healthOf('beta'), isNotNull, reason: 'saved unchanged');
      expect(store.healthOf('mine'), isNull, reason: 'removed, added again');
    });

    test('that are malformed are skipped without losing the sources', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'sources': [_source('mine').toJson()],
          'enabledIds': ['alpha'],
          'health': {
            'alpha': checked.toJson(),
            'beta': {'checkedAt': 'yesterday', 'reachable': true},
            'gamma': 'fine',
            'mine': {
              'checkedAt': '2026-11-12T10:00:00Z',
              'reachable': false,
              'readable': true,
              'pingMs': -4,
            },
          },
        }),
      );

      final store = await open();

      expect(store.savedFileWasUnreadable, isFalse);
      expect(ids(store), ['alpha', 'beta', 'gamma', 'mine']);
      expect(store.isEnabled('alpha'), isTrue);
      expect(store.healthOf('alpha')!.readable, isTrue);
      expect(store.healthOf('beta'), isNull);
      expect(store.healthOf('gamma'), isNull);
      // "Readable but unreachable" makes no sense, nor does a negative ping.
      expect(store.healthOf('mine')!.readable, isFalse);
      expect(store.healthOf('mine')!.ping, isNull);
    });

    test('a "health" value of the wrong kind is ignored', () async {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({'schemaVersion': 1, 'sources': <Object>[], 'health': 7}),
      );

      final store = await open();

      expect(store.savedFileWasUnreadable, isFalse);
      expect(store.sources, _starter);
    });
  });

  group('import and export', () {
    test('a preview tells new, changed and unchanged sources apart', () async {
      final store = await open();
      final changed = _source('beta', name: 'Beta, renamed');

      final preview = store.previewImport([
        _source('alpha'),
        changed,
        _source('one'),
        _source('two'),
      ]);

      expect(preview.added, [_source('one'), _source('two')]);
      expect(preview.changed, [changed]);
      expect(preview.unchanged, 1);
      expect(preview.changesNothing, isFalse);
      expect(store.sources, _starter, reason: 'a preview changes nothing');
      expect(store.previewImport([_source('alpha')]).changesNothing, isTrue);
    });

    test('an import adds new sources and replaces known ones', () async {
      final store = await open();
      final changed = _source('beta', name: 'Beta, renamed');

      await store.importSources([_source('alpha'), changed, _source('one')]);

      expect(ids(store), ['alpha', 'beta', 'gamma', 'one']);
      final reopened = await open();
      expect(reopened.sources[1], changed);
      expect(reopened.sources.last, _source('one'));
    });

    test('an import enables nothing and switches off what it replaced',
        () async {
      final store = await open();
      await store.setEnabled(['alpha', 'beta'], enabled: true);
      await store.recordHealth({
        for (final id in ['alpha', 'beta'])
          id: SourceHealth(
            checkedAt: DateTime(2026, 11, 12),
            reachable: true,
            readable: true,
          ),
      });

      await store.importSources([
        _source('alpha'),
        _source('beta', url: 'http://10.66.66.66/'),
        _source('one'),
      ]);

      expect(store.isEnabled('alpha'), isTrue, reason: 'unchanged');
      expect(store.isEnabled('beta'), isFalse, reason: 'points elsewhere now');
      expect(store.isEnabled('one'), isFalse);
      expect(store.healthOf('alpha'), isNotNull);
      expect(store.healthOf('beta'), isNull);
    });

    test('an import brings back a removed starter source', () async {
      final store = await open();
      await store.remove('beta');

      await store.importSources(_starter);

      expect(store.sources, _starter);
      expect(saved()['removedIds'], isEmpty);
    });

    test('an import that changes nothing writes nothing', () async {
      final store = await open();

      await store.importSources(_starter);

      expect(file.existsSync(), isFalse);
    });

    test('the export is a source list the app can read back', () async {
      final store = await open();
      await store.add(_source('mine'));
      await store.remove('alpha');
      await store.setEnabled(['beta'], enabled: true);

      final exported = store.exportJson();

      expect(parseSourceList(exported), store.sources);
      final root = jsonDecode(exported) as Map<String, dynamic>;
      expect(root.keys, ['schemaVersion', 'sources']);
      expect(exported, contains('\n  "sources": ['), reason: 'indented');
    });
  });

  test('reports a failed save but keeps the change for this run', () async {
    // A folder where the file should be makes every write fail.
    Directory(file.path).createSync(recursive: true);
    final store = SourceStore(starter: _starter, file: file);

    await expectLater(
      store.setEnabled(['alpha'], enabled: true),
      throwsA(isA<FileSystemException>()),
    );

    expect(store.isEnabled('alpha'), isTrue);
    // A later write is still attempted rather than stuck behind the failure.
    await expectLater(
      store.setEnabled(['beta'], enabled: true),
      throwsA(isA<FileSystemException>()),
    );
  });
}
