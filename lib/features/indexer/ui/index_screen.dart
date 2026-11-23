import 'dart:async';

import 'package:dhara/features/indexer/crawler.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/indexer/index_store.dart';
import 'package:dhara/features/player/player_screen.dart';
import 'package:dhara/features/snapshot/snapshot_controller.dart';
import 'package:dhara/features/snapshot/snapshot_format.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/shell/page_bleed.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/page_parts.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// Asks the user where a snapshot is to be saved, in the system's own
/// dialog, and returns the path, or `null` if they cancel.
Future<String?> askSnapshotPath() async {
  final location = await getSaveLocation(
    suggestedName: snapshotFileName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Library snapshot', extensions: ['gz']),
    ],
  );
  return location?.path;
}

/// The library index: how much of each enabled server has been read, the
/// buttons to update it, and a plain search over the files that were
/// found (the Search page looks for titles; this one for file names).
///
/// Opened from Settings. Every piece of server-supplied text (file names,
/// folder paths, messages) is shown through plain `Text` widgets only.
class IndexScreen extends StatefulWidget {
  const IndexScreen({super.key, this.pickSnapshotPath = askSnapshotPath});

  /// Asks where a snapshot of the library is to be saved.
  final Future<String?> Function() pickSnapshotPath;

  @override
  State<IndexScreen> createState() => _IndexScreenState();
}

class _IndexScreenState extends State<IndexScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  var _searches = 0;

  /// What the last search found; `null` while nothing is being searched.
  List<FileHit>? _hits;

  IndexController get _index => IndexScope.read(context);

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 150),
      () => unawaited(_search(text)),
    );
  }

  Future<void> _search(String text) async {
    final number = ++_searches;
    final hits = text.trim().isEmpty ? null : await _index.search(text);
    // Only the answer to the latest search counts.
    if (!mounted || number != _searches) return;
    setState(() => _hits = hits);
  }

  Future<void> _writeSnapshot(LibrarySnapshotController snapshots) async {
    final path = await widget.pickSnapshotPath();
    if (path != null) await snapshots.write(path);
  }

  void _play(FileHit hit) => unawaited(
    // Above the shell: the player takes the whole window.
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => PlayerScreen.urls([hit.url])),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final index = IndexScope.of(context);
    final sources = index.crawlableSources;
    final websites = index.unreadableSources;
    final hits = _hits;
    final running = index.isRunning;
    final snapshots = LibrarySnapshotScope.maybeOf(context);
    final snapshotStatus = snapshots == null ? null : _statusOf(snapshots);
    const sides = EdgeInsets.only(
      left: PageInsets.contentLeft,
      right: DharaLayout.pageRight,
    );

    return ColoredBox(
      key: const Key('library-index'),
      color: DharaColors.bg,
      // The text field is Material's.
      child: Material(
        type: MaterialType.transparency,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: sides.copyWith(top: 1.8 * rem),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageHead(
                      title: 'Library index',
                      subtitle:
                          'Reads the folders of your enabled servers and '
                          'keeps a list of every video, so search is '
                          'instant. Only enabled servers are contacted, a '
                          'few folders at a time.',
                      actions: [
                        if (sources.isNotEmpty)
                          DharaButton(
                            key: const Key('index-start-stop'),
                            style: DharaButtonStyle.primary,
                            icon: running
                                ? DharaIcons.stop
                                : DharaIcons.refresh,
                            label: !running
                                ? 'Update index'
                                : index.isStopping
                                ? 'Stopping …'
                                : 'Stop',
                            onPressed: running
                                ? index.stop
                                : () => unawaited(index.start()),
                          ),
                        if (sources.isNotEmpty && !running)
                          DharaButton(
                            key: const Key('index-full'),
                            icon: DharaIcons.recheck,
                            label: 'Full re-check',
                            tooltip:
                                'Reads every folder again, also those that '
                                'look unchanged',
                            onPressed: () => unawaited(index.start(full: true)),
                          ),
                        if (snapshots != null)
                          DharaButton(
                            key: const Key('index-snapshot'),
                            icon: DharaIcons.exportFile,
                            label: snapshots.isWriting
                                ? 'Writing …'
                                : 'Write snapshot',
                            tooltip:
                                'Writes the library to a file that a '
                                'production build starts from',
                            onPressed: snapshots.canWrite
                                ? () => unawaited(_writeSnapshot(snapshots))
                                : null,
                          ),
                      ],
                    ),
                    if (snapshots != null && snapshotStatus != null) ...[
                      const SizedBox(height: rem),
                      Text(
                        snapshotStatus,
                        key: const Key('index-snapshot-status'),
                        style: TextStyle(
                          fontFamily: DharaFonts.ui,
                          fontSize: DharaType.sm,
                          height: 1.4,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: snapshots.failed
                              ? DharaColors.warn
                              : DharaColors.text2,
                        ),
                      ),
                    ],
                    if (index.startupNotice case final notice?) ...[
                      const SizedBox(height: rem),
                      NoticeBar(notice),
                    ],
                    if (index.failedUnexpectedly) ...[
                      const SizedBox(height: rem),
                      const NoticeBar(
                        'Indexing stopped because of an error in the app. '
                        'What was found so far is kept.',
                      ),
                    ],
                    const SizedBox(height: 1.4 * rem),
                    _Stats(index: index, sources: sources),
                    const SizedBox(height: 1.4 * rem),
                    DharaField(
                      key: const Key('index-search'),
                      controller: _query,
                      onChanged: _onQueryChanged,
                      icon: DharaIcons.search,
                      hint: 'Search the files: a name, a year, S01E02 …',
                    ),
                    const SizedBox(height: 1.2 * rem),
                    CapsLabel(
                      hits == null
                          ? 'Enabled servers'
                          : hits.isEmpty
                          ? 'Nothing found'
                          : hits.length == 1
                          ? '1 file'
                          : '${hits.length} files, best match first',
                    ),
                    const SizedBox(height: .6 * rem),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: sides,
              sliver: hits != null
                  ? SliverList.builder(
                      itemCount: hits.length,
                      itemBuilder: (context, i) => _HitRow(
                        hit: hits[i],
                        source: _sourceOf(index, hits[i].sourceId),
                        onPlay: _play,
                      ),
                    )
                  : sources.isEmpty && websites.isEmpty
                  ? const SliverToBoxAdapter(child: _NoSources())
                  : SliverList.list(
                      children: [
                        for (final source in sources)
                          _SourceRow(
                            key: ValueKey(source.id),
                            source: source,
                            index: index,
                          ),
                        // Switched on, but nothing the app can read: said
                        // here, or the server would seem to be missing.
                        for (final source in websites)
                          _WebsiteRow(key: ValueKey(source.id), source: source),
                      ],
                    ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: DharaSpace.s7)),
          ],
        ),
      ),
    );
  }
}

/// What to say about the snapshot being written or written last, if
/// anything.
String? _statusOf(LibrarySnapshotController snapshots) {
  if (snapshots.isWriting) {
    return snapshots.rowsTotal == 0
        ? 'Writing the snapshot …'
        : 'Writing the snapshot … ${snapshots.rowsDone} of '
              '${snapshots.rowsTotal} rows';
  }
  if (snapshots.failed) {
    return 'The snapshot could not be written there. Nothing was left '
        'behind; pick another folder and try again.';
  }
  final written = snapshots.written;
  if (written == null) return null;
  return 'Snapshot written: ${written.videos} videos and ${written.titles} '
      'titles in ${_size(written.bytes)} · ${written.path}';
}

Source? _sourceOf(IndexController index, String id) {
  for (final source in index.sources.sources) {
    if (source.id == id) return source;
  }
  return null;
}

class _Stats extends StatelessWidget {
  const _Stats({required this.index, required this.sources});

  final IndexController index;
  final List<Source> sources;

  @override
  Widget build(BuildContext context) {
    var videos = 0;
    var indexed = 0;
    DateTime? oldest;
    for (final source in sources) {
      videos += _videosOf(index, source.id);
      final finished = index.statsOf(source.id)?.crawlFinishedAt;
      if (finished == null) continue;
      indexed++;
      if (oldest == null || finished.isBefore(oldest)) oldest = finished;
    }
    return StatRow(
      tiles: [
        StatTile(label: 'Videos', value: '$videos', note: 'on enabled servers'),
        StatTile(
          label: 'Servers indexed',
          value: '$indexed / ${sources.length}',
          valueColor: indexed == sources.length && indexed > 0
              ? DharaColors.good
              : DharaColors.text,
          note: 'read to the end at least once',
        ),
        StatTile(
          label: 'Oldest update',
          value: oldest == null ? '–' : _ago(index.now.difference(oldest)),
          note: 'updated by itself once a day',
        ),
      ],
    );
  }
}

/// The videos of a source in the index, counting what the crawl under way
/// has added and removed so far.
int _videosOf(IndexController index, String sourceId) {
  final known = index.statsOf(sourceId)?.files ?? 0;
  final progress = index.progressOf(sourceId);
  if (progress == null || progress.state != CrawlState.running) return known;
  return known + progress.filesAdded - progress.filesRemoved;
}

const _nameStyle = TextStyle(
  fontFamily: DharaFonts.ui,
  fontSize: DharaType.md,
  fontWeight: DharaType.semibold,
  color: DharaColors.text,
);

class _SourceRow extends StatelessWidget {
  const _SourceRow({super.key, required this.source, required this.index});

  final Source source;
  final IndexController index;

  @override
  Widget build(BuildContext context) {
    final (text, color) = _status();
    return RowCard(
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              source.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _nameStyle,
            ),
          ),
          const SizedBox(width: rem),
          Expanded(
            flex: 6,
            child: Text(
              text,
              key: Key('index-status-${source.id}'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: DharaFonts.ui,
                fontSize: DharaType.sm,
                height: 1.35,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: rem),
          SizedBox(
            width: 7.5 * rem,
            child: Text(
              '${_videosOf(index, source.id)} videos',
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontFamily: DharaFonts.ui,
                fontSize: DharaType.sm,
                fontFeatures: [FontFeature.tabularFigures()],
                color: DharaColors.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What to say about this source, and in which colour.
  (String, Color) _status() {
    final progress = index.progressOf(source.id);
    final stats = index.statsOf(source.id);
    if (progress != null) {
      final folders = progress.foldersRead == 1
          ? '1 folder'
          : '${progress.foldersRead} folders';
      switch (progress.state) {
        case CrawlState.running:
          final folder = progress.folder;
          return (
            folder == null || folder.isEmpty
                ? 'Reading … $folders so far'
                : 'Reading … $folders so far · $folder',
            DharaColors.accent2,
          );
        case CrawlState.complete:
          return (
            progress.message ?? 'Up to date · $folders read just now',
            progress.message == null ? DharaColors.good : DharaColors.warn,
          );
        case CrawlState.incomplete || CrawlState.stopped || CrawlState.skipped:
          return (progress.message ?? 'Not finished', DharaColors.warn);
        case CrawlState.cancelled:
          return (
            'Stopped · carries on from here next time',
            DharaColors.text2,
          );
      }
    }
    if (index.isRunning) return ('Waiting for its turn …', DharaColors.text3);
    if (stats == null) return ('Not indexed yet', DharaColors.text3);
    if (stats.lastError case final error?) return (error, DharaColors.warn);
    final finished = stats.crawlFinishedAt;
    if (finished == null || stats.pendingFolders > 0) {
      return (
        'Unfinished · ${stats.pendingFolders} folders still to read',
        DharaColors.warn,
      );
    }
    return (
      'Indexed ${_ago(index.now.difference(finished))}',
      DharaColors.text2,
    );
  }
}

/// An enabled source the app has no adapter for: a website of some other
/// kind than a folder listing or a media server.
class _WebsiteRow extends StatelessWidget {
  const _WebsiteRow({super.key, required this.source});

  final Source source;

  @override
  Widget build(BuildContext context) {
    return RowCard(
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              source.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _nameStyle.copyWith(color: DharaColors.text2),
            ),
          ),
          const SizedBox(width: rem),
          Expanded(
            flex: 6,
            child: Text(
              'A website, which Dhara cannot read yet: it is not indexed, '
              'and nothing of it is in your library.',
              key: Key('index-status-${source.id}'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: DharaFonts.ui,
                fontSize: DharaType.sm,
                height: 1.35,
                color: DharaColors.warn,
              ),
            ),
          ),
          const SizedBox(width: rem),
          const SizedBox(
            width: 7.5 * rem,
            child: Text(
              'not counted',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontFamily: DharaFonts.ui,
                fontSize: DharaType.sm,
                color: DharaColors.text3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HitRow extends StatelessWidget {
  const _HitRow({
    required this.hit,
    required this.source,
    required this.onPlay,
  });

  final FileHit hit;
  final Source? source;
  final ValueChanged<FileHit> onPlay;

  @override
  Widget build(BuildContext context) {
    // A media server wants its session token with every request, which
    // the player cannot send yet.
    final type = source?.type;
    final playable = type != SourceType.emby && type != SourceType.jellyfin;
    final size = hit.size;
    final details = [
      source?.name ?? hit.sourceId,
      if (hit.path.isNotEmpty) hit.path,
      if (size != null) _size(size),
      if (!playable) 'cannot be played yet',
    ].join('  ·  ');

    return RowCard(
      onPressed: playable ? () => onPlay(hit) : null,
      semanticLabel: playable ? 'Play ${hit.name}' : null,
      child: Row(
        children: [
          Icon(
            playable ? DharaIcons.play : DharaIcons.locked,
            size: 1.35 * rem,
            color: playable ? DharaColors.text2 : DharaColors.text3,
          ),
          const SizedBox(width: .8 * rem),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _nameStyle,
                ),
                Text(
                  details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: DharaFonts.ui,
                    fontSize: DharaType.xs,
                    height: 1.4,
                    color: DharaColors.text3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoSources extends StatelessWidget {
  const _NoSources();

  @override
  Widget build(BuildContext context) {
    return const GlassCard(
      child: Center(
        child: EmptyState(
          icon: DharaIcons.servers,
          title: 'No servers to index',
          message: 'Test and enable servers in Server Discovery first.',
        ),
      ),
    );
  }
}

/// "3 h ago" for a time that long past.
String _ago(Duration age) {
  if (age.inMinutes < 1) return 'just now';
  if (age.inHours < 1) return '${age.inMinutes} min ago';
  if (age.inDays < 1) return '${age.inHours} h ago';
  return age.inDays == 1 ? '1 day ago' : '${age.inDays} days ago';
}

/// A file size the way people say it: "1.6 GB", "700 MB".
String _size(int bytes) {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  return '${(bytes / 1024).ceil()} KB';
}
