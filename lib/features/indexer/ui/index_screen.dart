import 'dart:async';

import 'package:dhara/features/indexer/crawler.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/indexer/index_store.dart';
import 'package:dhara/features/player/player_screen.dart';
import 'package:dhara/features/player/widgets/glass.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// The library index: how much of each enabled server has been read, the
/// buttons to update it, and a plain search over what was found.
///
/// A working screen until the real Home and Search screens arrive in
/// Phase 6. Every piece of server-supplied text (file names, folder paths,
/// messages) is shown through plain `Text` widgets only.
class IndexScreen extends StatefulWidget {
  const IndexScreen({super.key});

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

  void _play(FileHit hit) => unawaited(
    // Above the shell: the player takes the whole window.
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => PlayerScreen(urls: [hit.url])),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final index = IndexScope.of(context);
    final sources = index.crawlableSources;
    final hits = _hits;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) {
          final gutter = box.maxWidth >= 900 ? 40.0 : 20.0;
          final sides = EdgeInsets.symmetric(horizontal: gutter);
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: sides.copyWith(top: 28),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(index: index, canStart: sources.isNotEmpty),
                      if (index.startupNotice case final notice?) ...[
                        const SizedBox(height: 16),
                        _Notice(notice),
                      ],
                      if (index.failedUnexpectedly) ...[
                        const SizedBox(height: 16),
                        const _Notice(
                          'Indexing stopped because of an error in the app. '
                          'What was found so far is kept.',
                        ),
                      ],
                      const SizedBox(height: 22),
                      _Stats(index: index, sources: sources),
                      const SizedBox(height: 22),
                      TextField(
                        key: const Key('index-search'),
                        controller: _query,
                        onChanged: _onQueryChanged,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText:
                              'Search the index: a title, a year, S01E02 …',
                        ),
                      ),
                      const SizedBox(height: 14),
                      PanelHeading(
                        hits == null
                            ? 'Enabled servers'
                            : hits.isEmpty
                            ? 'Nothing found'
                            : hits.length == 1
                            ? '1 file'
                            : '${hits.length} files, best match first',
                      ),
                      const SizedBox(height: 8),
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
                    : sources.isEmpty
                    ? const SliverToBoxAdapter(child: _NoSources())
                    : SliverList.builder(
                        itemCount: sources.length,
                        itemBuilder: (context, i) => _SourceRow(
                          key: ValueKey(sources[i].id),
                          source: sources[i],
                          index: index,
                        ),
                      ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 36)),
            ],
          );
        },
      ),
    );
  }
}

Source? _sourceOf(IndexController index, String id) {
  for (final source in index.sources.sources) {
    if (source.id == id) return source;
  }
  return null;
}

class _Header extends StatelessWidget {
  const _Header({required this.index, required this.canStart});

  final IndexController index;
  final bool canStart;

  @override
  Widget build(BuildContext context) {
    final running = index.isRunning;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 16,
      runSpacing: 14,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Library index',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Reads the folders of your enabled servers and keeps '
                      'a list of every video, so search is instant. Only '
                      'enabled servers are contacted, a few folders at a '
                      'time.',
                      style: TextStyle(fontSize: 13, color: DharaColors.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (canStart)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DharaPillButton(
                key: const Key('index-start-stop'),
                primary: true,
                icon: running ? Icons.stop_rounded : Icons.refresh_rounded,
                label: !running
                    ? 'Update index'
                    : index.isStopping
                    ? 'Stopping …'
                    : 'Stop',
                onPressed: running
                    ? index.stop
                    : () => unawaited(index.start()),
              ),
              if (!running)
                DharaPillButton(
                  key: const Key('index-full'),
                  icon: Icons.restart_alt_rounded,
                  label: 'Full re-check',
                  onPressed: () => unawaited(index.start(full: true)),
                ),
            ],
          ),
      ],
    );
  }
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
    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Videos',
            value: '$videos',
            note: 'on enabled servers',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatCard(
            label: 'Servers indexed',
            value: '$indexed / ${sources.length}',
            valueColor: indexed == sources.length && indexed > 0
                ? DharaColors.good
                : DharaColors.text,
            note: 'read to the end at least once',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatCard(
            label: 'Oldest update',
            value: oldest == null ? '–' : _ago(index.now.difference(oldest)),
            note: 'updated by itself once a day',
          ),
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

class _SourceRow extends StatelessWidget {
  const _SourceRow({super.key, required this.source, required this.index});

  final Source source;
  final IndexController index;

  @override
  Widget build(BuildContext context) {
    final (text, color) = _status();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: _rowDecoration,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              source.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 6,
            child: Text(
              text,
              key: Key('index-status-${source.id}'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: color),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 110,
            child: Text(
              '${_videosOf(index, source.id)} videos',
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 13, color: DharaColors.text2),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(DharaRadii.md),
          onTap: playable ? () => onPlay(hit) : null,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: _rowDecoration,
            child: Row(
              children: [
                Icon(
                  playable ? Icons.play_arrow_rounded : Icons.lock_outline,
                  size: 20,
                  color: playable ? DharaColors.text2 : DharaColors.text3,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hit.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: DharaColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoSources extends StatelessWidget {
  const _NoSources();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 44),
      decoration: _rowDecoration,
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dns_outlined, color: DharaColors.text3, size: 30),
          SizedBox(height: 8),
          Text(
            'No servers to index',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4),
          Text(
            'Test and enable servers in Server Discovery first.',
            style: TextStyle(fontSize: 12.5, color: DharaColors.text2),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: DharaColors.surface,
        borderRadius: BorderRadius.circular(DharaRadii.md),
        border: Border.all(color: DharaColors.warn.withValues(alpha: .5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: DharaColors.warn),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

final _rowDecoration = BoxDecoration(
  color: DharaColors.surface,
  borderRadius: BorderRadius.circular(DharaRadii.md),
  border: Border.all(color: DharaColors.stroke),
);

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
