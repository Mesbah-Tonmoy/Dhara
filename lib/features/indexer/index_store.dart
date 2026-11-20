import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// A folder that is waiting to be read.
@immutable
class PendingFolder {
  const PendingFolder({
    required this.id,
    required this.url,
    required this.path,
    required this.depth,
  });

  final int id;
  final Uri url;

  /// The folder names from the base URL down, joined by "/"; empty for a
  /// base URL itself.
  final String path;

  /// 0 for a base URL.
  final int depth;
}

/// A video with the subtitle files that belong to it.
@immutable
class IndexedVideo {
  const IndexedVideo(this.file, [this.subtitles = const []]);

  final RemoteEntry file;
  final List<RemoteEntry> subtitles;
}

/// What reading one folder found, reduced to what the index keeps.
@immutable
class FolderListing {
  const FolderListing({this.folders = const [], this.videos = const []});

  /// The folders inside it that should be read as well.
  final List<RemoteEntry> folders;
  final List<IndexedVideo> videos;
}

/// What [IndexStore.saveListing] changed.
@immutable
class ListingChanges {
  const ListingChanges({
    this.filesAdded = 0,
    this.filesRemoved = 0,
    this.foldersAdded = 0,
  });

  final int filesAdded;

  /// Files that were in this folder before and are gone now. Files that
  /// went with a removed sub-folder are not counted.
  final int filesRemoved;
  final int foldersAdded;
}

/// How much of one source is in the index.
@immutable
class SourceIndexStats {
  const SourceIndexStats({
    required this.sourceId,
    required this.files,
    required this.folders,
    required this.pendingFolders,
    required this.failedFolders,
    this.crawlStartedAt,
    this.crawlFinishedAt,
    this.lastError,
  });

  final String sourceId;
  final int files;
  final int folders;

  /// Folders still to be read; above zero while a crawl is unfinished.
  final int pendingFolders;

  /// Folders the last crawl could not read.
  final int failedFolders;
  final DateTime? crawlStartedAt;

  /// When a crawl last reached the end.
  final DateTime? crawlFinishedAt;
  final String? lastError;
}

/// One search result. [name] and [path] are server-controlled text: show
/// them only through a plain `Text` widget.
@immutable
class FileHit {
  const FileHit({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.path,
    required this.url,
    this.size,
    this.modified,
  });

  final int id;
  final String sourceId;
  final String name;

  /// The folders it is in, below the source's base URL.
  final String path;
  final Uri url;
  final int? size;
  final DateTime? modified;
}

/// Reads and writes the index part of the library database: the crawl
/// queue, the files and subtitles found, and search.
///
/// A crawl of a source goes: [beginCrawl], then [pendingFolders] and
/// [saveListing] (or [markFailed]) until nothing is pending, then
/// [finishCrawl]. Everything is kept as it goes, so a crawl that was cut
/// short carries on where it stopped.
///
/// Every value goes into SQL as a parameter, never as text.
class IndexStore {
  IndexStore(this._library, {DateTime Function() now = DateTime.now})
    : _clock = now;

  final LibraryDb _library;
  final DateTime Function() _clock;

  Database get _db => _library.db;
  int get _now => _clock().millisecondsSinceEpoch;

  late final _folderByUrl = _db.prepare(
    'SELECT id, parent, path, modified, leaf, state FROM folders '
    'WHERE url = ?',
  );
  late final _insertFolder = _db.prepare(
    'INSERT INTO folders (source, parent, url, path, depth, modified) '
    'VALUES (?, ?, ?, ?, ?, ?)',
  );
  late final _insertFile = _db.prepare(
    'INSERT INTO files (folder, name, url, size, modified, added_at) '
    'VALUES (?, ?, ?, ?, ?, ?)',
  );
  late final _insertSubtitle = _db.prepare(
    'INSERT INTO subtitles (file, name, url) VALUES (?, ?, ?)',
  );

  /// Gets the source ready to be crawled and returns its key for the other
  /// calls.
  ///
  /// If the last crawl was cut short, it carries on: only the folders not
  /// read yet are pending. Otherwise a new crawl starts at the [baseUrls].
  /// Folders below a base URL the source no longer has are removed.
  ///
  /// With [full], every folder is read again, also those the server says
  /// have not changed.
  int beginCrawl(String sourceId, List<Uri> baseUrls, {bool full = false}) =>
      _library.transaction(() {
        _db.execute(
          'INSERT INTO sources (source_id) VALUES (?) '
          'ON CONFLICT (source_id) DO NOTHING',
          [sourceId],
        );
        final row = _db.select(
          'SELECT id, crawl_started_at, crawl_finished_at FROM sources '
          'WHERE source_id = ?',
          [sourceId],
        ).single;
        final source = row['id'] as int;
        final started = row['crawl_started_at'] as int?;
        final finished = row['crawl_finished_at'] as int?;

        final urls = [for (final url in baseUrls) url.toString()];
        _db.execute(
          'DELETE FROM folders WHERE source = ? AND parent IS NULL '
          'AND url NOT IN (${_placeholders(urls.length)})',
          [source, ...urls],
        );
        for (final url in urls) {
          // A URL that is already known as a folder of another base URL
          // (or source) is read there.
          _db.execute(
            'INSERT INTO folders (source, url, path, depth) '
            "VALUES (?, ?, '', 0) ON CONFLICT (url) DO NOTHING",
            [source, url],
          );
        }
        // Failures get a new chance every time.
        _db.execute(
          'UPDATE folders SET state = 0 WHERE source = ? AND state = 2',
          [source],
        );

        final cutShort =
            started != null &&
            (finished == null || finished < started) &&
            _db.select(
              'SELECT 1 FROM folders WHERE source = ? AND state = 0 LIMIT 1',
              [source],
            ).isNotEmpty;
        if (full) {
          // Without the dates no folder can pass as unchanged, and that
          // holds even if this crawl is cut short and carried on later.
          _db.execute('UPDATE folders SET modified = NULL WHERE source = ?', [
            source,
          ]);
        }
        if (full || !cutShort) {
          _db.execute(
            'UPDATE folders SET state = 0 '
            'WHERE source = ? AND parent IS NULL',
            [source],
          );
          _db.execute('UPDATE sources SET crawl_started_at = ? WHERE id = ?', [
            _now,
            source,
          ]);
        }
        return source;
      });

  /// How many folders of [source] the index holds.
  int folderCount(int source) =>
      _db.select('SELECT count(*) AS n FROM folders WHERE source = ?', [
            source,
          ]).single['n']
          as int;

  /// Up to [limit] folders of [source] that are waiting to be read, upper
  /// levels first.
  List<PendingFolder> pendingFolders(int source, {int limit = 50}) => [
    for (final row in _db.select(
      'SELECT id, url, path, depth FROM folders '
      'WHERE source = ? AND state = 0 ORDER BY id LIMIT ?',
      [source, limit],
    ))
      PendingFolder(
        id: row['id'] as int,
        url: Uri.parse(row['url'] as String),
        path: row['path'] as String,
        depth: row['depth'] as int,
      ),
  ];

  /// Makes the index match what reading [folder] found, and marks the
  /// folder as read.
  ///
  /// New videos and folders are added; those no longer listed are removed
  /// with everything below them. A folder inside is queued to be read
  /// unless it can be skipped: it was read before, held no folders then,
  /// and the server reports the same change date as last time.
  ///
  /// Folders deeper than [maxDepth] are left out, and at most
  /// [folderBudget] new ones are added.
  ListingChanges saveListing(
    PendingFolder folder,
    FolderListing listing, {
    required int maxDepth,
    required int folderBudget,
  }) => _library.transaction(() {
    // Gone meanwhile: its parent was read again, or its source removed.
    final self = _db.select('SELECT source FROM folders WHERE id = ?', [
      folder.id,
    ]);
    if (self.isEmpty) return const ListingChanges();

    final foldersAdded = _saveFolders(
      folder,
      self.single['source'] as int,
      folder.depth < maxDepth ? listing.folders : const [],
      folderBudget,
    );
    final (filesAdded, filesRemoved) = _saveVideos(folder, listing.videos);
    _db.execute(
      'UPDATE folders SET state = 1, leaf = ?, listed_at = ? WHERE id = ?',
      [if (listing.folders.isEmpty) 1 else 0, _now, folder.id],
    );
    return ListingChanges(
      filesAdded: filesAdded,
      filesRemoved: filesRemoved,
      foldersAdded: foldersAdded,
    );
  });

  /// Returns how many folders were added.
  int _saveFolders(
    PendingFolder folder,
    int source,
    List<RemoteEntry> entries,
    int budget,
  ) {
    var added = 0;
    final kept = <int>{};
    final seen = <String>{};
    for (final entry in entries) {
      final url = entry.url.toString();
      if (!seen.add(url)) continue;
      final path = folder.path.isEmpty
          ? entry.name
          : '${folder.path}/${entry.name}';
      final modified = entry.modified?.millisecondsSinceEpoch;

      final known = _folderByUrl.select([url]);
      if (known.isNotEmpty) {
        final row = known.first;
        final id = row['id'] as int;
        // Reached another way already; it is read there.
        if (row['parent'] != folder.id) continue;
        if (row['path'] == path) {
          final unchanged =
              row['state'] == 1 &&
              row['leaf'] == 1 &&
              modified != null &&
              row['modified'] == modified;
          if (!unchanged) {
            _db.execute(
              'UPDATE folders SET state = 0, modified = ? WHERE id = ?',
              [modified, id],
            );
          }
          kept.add(id);
          continue;
        }
        // Renamed in place (a media server keeps the address). The search
        // index holds the old path, so it starts over as a new folder.
        _db.execute('DELETE FROM folders WHERE id = ?', [id]);
      }
      if (added >= budget) continue;
      _insertFolder.execute([
        source,
        folder.id,
        url,
        path,
        folder.depth + 1,
        modified,
      ]);
      kept.add(_db.lastInsertRowId);
      added++;
    }

    final children = _db.select('SELECT id FROM folders WHERE parent = ?', [
      folder.id,
    ]);
    for (final row in children) {
      final id = row['id'] as int;
      if (!kept.contains(id)) {
        _db.execute('DELETE FROM folders WHERE id = ?', [id]);
      }
    }
    return added;
  }

  /// Returns how many files were added and how many removed.
  (int, int) _saveVideos(PendingFolder folder, List<IndexedVideo> videos) {
    final known = {
      for (final row in _db.select(
        'SELECT id, name, url, size, modified, added_at FROM files '
        'WHERE folder = ?',
        [folder.id],
      ))
        row['url'] as String: row,
    };
    final knownSubtitles = <int, List<String>>{};
    if (known.isNotEmpty) {
      for (final row in _db.select(
        'SELECT s.file, s.url FROM subtitles s '
        'JOIN files f ON f.id = s.file WHERE f.folder = ? ORDER BY s.id',
        [folder.id],
      )) {
        (knownSubtitles[row['file'] as int] ??= []).add(row['url'] as String);
      }
    }

    var added = 0;
    final seen = <String>{};
    final now = _now;
    for (final video in videos) {
      final file = video.file;
      final url = file.url.toString();
      if (!seen.add(url)) continue;
      final modified = file.modified?.millisecondsSinceEpoch;
      final subtitles = {
        for (final subtitle in video.subtitles)
          subtitle.url.toString(): subtitle.name,
      };

      final old = known.remove(url);
      if (old != null && old['name'] == file.name) {
        final id = old['id'] as int;
        if (old['size'] != file.size || old['modified'] != modified) {
          _db.execute('UPDATE files SET size = ?, modified = ? WHERE id = ?', [
            file.size,
            modified,
            id,
          ]);
        }
        if (!listEquals(knownSubtitles[id] ?? const [], [...subtitles.keys])) {
          _db.execute('DELETE FROM subtitles WHERE file = ?', [id]);
          _addSubtitles(id, subtitles);
        }
        continue;
      }
      if (old == null) {
        added++;
      } else {
        // Renamed in place: the search index holds the old name, so the
        // row is replaced. It is still the same file, added when it was.
        _db.execute('DELETE FROM files WHERE id = ?', [old['id']]);
      }
      _insertFile.execute([
        folder.id,
        file.name,
        url,
        file.size,
        modified,
        old?['added_at'] ?? now,
      ]);
      _addSubtitles(_db.lastInsertRowId, subtitles);
    }

    for (final row in known.values) {
      _db.execute('DELETE FROM files WHERE id = ?', [row['id']]);
    }
    return (added, known.length);
  }

  void _addSubtitles(int file, Map<String, String> nameByUrl) {
    for (final MapEntry(key: url, value: name) in nameByUrl.entries) {
      _insertSubtitle.execute([file, name, url]);
    }
  }

  /// Marks a folder that could not be read. What the index holds of it
  /// stays; the next crawl tries it again.
  void markFailed(int folderId) =>
      _db.execute('UPDATE folders SET state = 2 WHERE id = ?', [folderId]);

  /// Ends this run of the crawl of [source]. If no folder is left waiting,
  /// the crawl counts as complete. [error] says why it stopped early, or
  /// what went wrong on the way.
  void finishCrawl(int source, {String? error}) => _db.execute(
    'UPDATE sources SET last_error = ?2, crawl_finished_at = CASE '
    'WHEN EXISTS (SELECT 1 FROM folders WHERE source = ?1 AND state = 0) '
    'THEN crawl_finished_at ELSE ?3 END WHERE id = ?1',
    [source, error, _now],
  );

  /// Removes every source that is not in [sourceIds] (the ids in the source
  /// list), with everything found on it.
  void removeSourcesExcept(Iterable<String> sourceIds) {
    final ids = sourceIds.toList();
    _db.execute(
      'DELETE FROM sources '
      'WHERE source_id NOT IN (${_placeholders(ids.length)})',
      ids,
    );
    // A source takes a large part of the file with it.
    if (_db.updatedRows > 0) _library.releaseFreeSpace();
  }

  /// What the index holds of every source that was ever crawled.
  List<SourceIndexStats> stats() => [
    for (final row in _db.select(
      'SELECT s.source_id, s.crawl_started_at, s.crawl_finished_at, '
      's.last_error, '
      '(SELECT count(*) FROM folders d WHERE d.source = s.id) AS folders, '
      '(SELECT count(*) FROM folders d '
      'WHERE d.source = s.id AND d.state = 0) AS pending, '
      '(SELECT count(*) FROM folders d '
      'WHERE d.source = s.id AND d.state = 2) AS failed, '
      '(SELECT count(*) FROM files f JOIN folders d ON d.id = f.folder '
      'WHERE d.source = s.id) AS files '
      'FROM sources s ORDER BY s.id',
    ))
      SourceIndexStats(
        sourceId: row['source_id'] as String,
        files: row['files'] as int,
        folders: row['folders'] as int,
        pendingFolders: row['pending'] as int,
        failedFolders: row['failed'] as int,
        crawlStartedAt: _time(row['crawl_started_at']),
        crawlFinishedAt: _time(row['crawl_finished_at']),
        lastError: row['last_error'] as String?,
      ),
  ];

  /// The files whose name or folders contain every word of [text], best
  /// match first. The last word may be unfinished, so results appear while
  /// the user is still typing. Only files of the sources in [sourceIds]
  /// are returned.
  List<FileHit> search(
    String text, {
    required Iterable<String> sourceIds,
    int limit = 50,
  }) {
    final query = ftsWordsQueryFor(text);
    final ids = sourceIds.toList();
    if (query == null || ids.isEmpty) return const [];
    return [
      for (final row in _db.select(
        'SELECT f.id, f.name, f.url, f.size, f.modified, d.path, s.source_id '
        'FROM files_fts '
        'JOIN files f ON f.id = files_fts.rowid '
        'JOIN folders d ON d.id = f.folder '
        'JOIN sources s ON s.id = d.source '
        'WHERE files_fts MATCH ? '
        'AND s.source_id IN (${_placeholders(ids.length)}) '
        'ORDER BY files_fts.rank LIMIT ?',
        [query, ...ids, limit],
      ))
        FileHit(
          id: row['id'] as int,
          sourceId: row['source_id'] as String,
          name: row['name'] as String,
          path: row['path'] as String,
          url: Uri.parse(row['url'] as String),
          size: row['size'] as int?,
          modified: _time(row['modified']),
        ),
    ];
  }
}

/// Turns what the user typed into an FTS5 query: every word must match,
/// the last one as a prefix. Each word is quoted, so nothing typed can act
/// as query syntax. Returns `null` if there is nothing to search for.
String? ftsQueryFor(String text) {
  final words = [
    for (final word in text.split(_whitespace))
      if (word.contains(_letterOrDigit)) word,
  ];
  if (words.isEmpty) return null;
  final quoted = [
    for (final word in words.take(_maxSearchWords))
      '"${word.replaceAll('"', '""')}"',
  ];
  return '${quoted.join(' ')}*';
}

/// As [ftsQueryFor], for an index that keeps no word order (the one over
/// file names): what is typed is cut at everything that is not a letter or
/// a digit, as the index cuts names, so "breaking.bad" asks for the two
/// words and not for one after the other.
String? ftsWordsQueryFor(String text) {
  final words = [
    for (final word in text.split(_notLetterOrDigit))
      if (word.isNotEmpty) word,
  ];
  if (words.isEmpty) return null;
  return '${[for (final word in words.take(_maxSearchWords)) '"$word"'].join(' ')}*';
}

final _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

const _maxSearchWords = 12;
final _whitespace = RegExp(r'\s+');
final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

DateTime? _time(Object? milliseconds) => milliseconds is int
    ? DateTime.fromMillisecondsSinceEpoch(milliseconds)
    : null;

/// "?, ?, ?" for [count] values. With none, a text no id or URL equals:
/// an empty `IN ()` is not valid SQL.
String _placeholders(int count) =>
    count == 0 ? "''" : List.filled(count, '?').join(', ');
