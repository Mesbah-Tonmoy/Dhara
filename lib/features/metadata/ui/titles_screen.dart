import 'dart:async';

import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/core/net/media_url.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/metadata/ui/match_panel.dart';
import 'package:dhara/features/metadata/ui/needs_review_screen.dart';
import 'package:dhara/features/metadata/ui/tmdb_key_card.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:dhara/features/player/player_screen.dart';
import 'package:dhara/features/player/widgets/glass.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Plays these addresses one after the other.
typedef PlayUrls = void Function(BuildContext context, List<Uri> urls);

void _openPlayer(BuildContext context, List<Uri> urls) => unawaited(
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => PlayerScreen(urls: urls))),
);

/// The films and shows the indexed videos are copies of: how many there
/// are, and a search by title.
///
/// A working screen until the real Home and Search screens arrive in
/// Phase 6. Titles, file names and folder paths come from the servers and
/// are shown through plain `Text` widgets only.
class TitlesScreen extends StatefulWidget {
  const TitlesScreen({super.key, this.onPlay = _openPlayer});

  /// What a tap on a copy does; the player by default.
  final PlayUrls onPlay;

  @override
  State<TitlesScreen> createState() => _TitlesScreenState();
}

class _TitlesScreenState extends State<TitlesScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  var _searches = 0;
  TitlesController? _titles;
  var _wasReading = false;
  MatchController? _match;
  MatchCounts? _countsSeen;

  /// What the last search found; `null` while nothing is being searched.
  List<TitleHit>? _hits;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final match = MatchScope.of(context);
    if (match != _match) {
      _match?.removeListener(_onMatchChanged);
      _match = match..addListener(_onMatchChanged);
      _countsSeen = match.counts;
    }
    final titles = TitlesScope.of(context);
    if (titles == _titles) return;
    _titles?.removeListener(_onTitlesChanged);
    _titles = titles..addListener(_onTitlesChanged);
    _wasReading = titles.isReading;
  }

  @override
  void dispose() {
    _titles?.removeListener(_onTitlesChanged);
    _match?.removeListener(_onMatchChanged);
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Names that were just read may change what a search finds.
  void _onTitlesChanged() {
    final reading = _titles!.isReading;
    if (_wasReading && !reading && _hits != null) {
      unawaited(_search(_query.text));
    }
    _wasReading = reading;
  }

  /// Titles that were matched, by a run or by hand, have other names and
  /// posters now.
  void _onMatchChanged() {
    final match = _match!;
    if (match.isRunning || identical(match.counts, _countsSeen)) return;
    _countsSeen = match.counts;
    if (_hits != null) unawaited(_search(_query.text));
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
    final hits = text.trim().isEmpty ? null : await _titles!.search(text);
    // Only the answer to the latest search counts.
    if (!mounted || number != _searches) return;
    setState(() => _hits = hits);
  }

  void _open(TitleHit hit) => unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TitleCopiesScreen(title: hit, onPlay: widget.onPlay),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final titles = TitlesScope.of(context);
    final tmdbKey = TmdbKeyScope.of(context);
    final match = MatchScope.of(context);
    final toReview = match.counts?.toReview ?? 0;
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
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 16,
                        runSpacing: 14,
                        children: [
                          const _Header(
                            title: 'Films and shows',
                            subtitle:
                                'Every copy of a film, and every episode of '
                                'a show, under one title: worked out from '
                                'the names of the files and folders in the '
                                'index.',
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (toReview > 0)
                                DharaPillButton(
                                  key: const Key('titles-review'),
                                  icon: Icons.rule_rounded,
                                  label: 'Needs review ($toReview)',
                                  onPressed: () => unawaited(
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            const NeedsReviewScreen(),
                                      ),
                                    ),
                                  ),
                                ),
                              DharaPillButton(
                                key: const Key('titles-tmdb-key'),
                                icon: Icons.key_outlined,
                                label: tmdbKey.hasKey
                                    ? 'TMDB key'
                                    : 'Add TMDB key',
                                onPressed: () => unawaited(
                                  showTmdbKeyDialog(context, tmdbKey),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (titles.failed) ...[
                        const SizedBox(height: 16),
                        const _Notice(
                          'The names of the videos could not be read '
                          'because of an error in the app.',
                        ),
                      ],
                      const SizedBox(height: 22),
                      _Stats(titles: titles),
                      const SizedBox(height: 14),
                      MatchPanel(match: match, tmdbKey: tmdbKey),
                      const SizedBox(height: 22),
                      TextField(
                        key: const Key('titles-search'),
                        controller: _query,
                        onChanged: _onQueryChanged,
                        autofocus: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText: 'Search films and shows by title …',
                        ),
                      ),
                      const SizedBox(height: 14),
                      PanelHeading(
                        hits == null
                            ? 'Type a title to search'
                            : hits.isEmpty
                            ? 'Nothing found'
                            : hits.length == 1
                            ? '1 title'
                            : '${hits.length} titles, best match first',
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              if (hits != null)
                SliverPadding(
                  padding: sides,
                  sliver: SliverList.builder(
                    itemCount: hits.length,
                    itemBuilder: (context, i) =>
                        _TitleRow(hit: hits[i], onOpen: _open),
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

class _Stats extends StatelessWidget {
  const _Stats({required this.titles});

  final TitlesController titles;

  @override
  Widget build(BuildContext context) {
    final counts = titles.counts;
    final reading = titles.isReading && titles.namesToRead > 0;
    String count(int? number) => number == null ? '–' : '$number';
    return Row(
      children: [
        Expanded(
          child: StatCard(
            key: const Key('titles-films'),
            label: 'Films',
            value: count(counts?.movies),
            note: reading
                ? 'Reading file names … ${titles.namesRead} / '
                      '${titles.namesToRead}'
                : 'one title, however many copies',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatCard(
            key: const Key('titles-shows'),
            label: 'Shows',
            value: count(counts?.shows),
            note: 'episodes grouped by season',
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatCard(
            key: const Key('titles-other'),
            label: 'Other videos',
            value: count(counts?.otherVideos),
            note: 'clips and songs, found by file name',
          ),
        ),
      ],
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.hit, required this.onOpen});

  final TitleHit hit;
  final ValueChanged<TitleHit> onOpen;

  @override
  Widget build(BuildContext context) {
    final isShow = hit.kind == TitleKind.series;
    final year = hit.year;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('title-${hit.id}'),
          borderRadius: BorderRadius.circular(DharaRadii.md),
          onTap: () => onOpen(hit),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            decoration: _rowDecoration,
            child: Row(
              children: [
                TmdbPicture(
                  path: hit.posterPath,
                  size: 'w154',
                  width: 30,
                  height: 45,
                  placeholder: isShow ? Icons.tv_rounded : Icons.movie_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    year == null ? hit.name : '${hit.name} ($year)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  _copiesLabel(hit.copies, isShow: isShow),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: DharaColors.text2,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: DharaColors.text3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _copiesLabel(int copies, {required bool isShow}) {
  if (isShow) return copies == 1 ? '1 video' : '$copies videos';
  return copies == 1 ? '1 copy' : '$copies copies';
}

/// The videos of one title: the copies of a film, or the episodes of a
/// show by season. A tap plays one; for a show, the episodes after it
/// follow.
class TitleCopiesScreen extends StatefulWidget {
  const TitleCopiesScreen({
    super.key,
    required this.title,
    this.onPlay = _openPlayer,
  });

  final TitleHit title;
  final PlayUrls onPlay;

  @override
  State<TitleCopiesScreen> createState() => _TitleCopiesScreenState();
}

class _TitleCopiesScreenState extends State<TitleCopiesScreen> {
  /// `null` until they have been read.
  List<TitleCopy>? _copies;
  var _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    unawaited(_load(TitlesScope.read(context)));
  }

  Future<void> _load(TitlesController titles) async {
    final copies = await titles.copiesOf(widget.title.id);
    if (mounted) setState(() => _copies = copies);
  }

  void _play(TitleCopy copy, List<TitleCopy> copies, IndexController index) {
    final queue = widget.title.kind == TitleKind.series
        ? episodesFrom(
            copies,
            copy,
            playable: (other) => _isPlayable(other, index),
          )
        : [copy];
    widget.onPlay(context, [for (final entry in queue) entry.url]);
  }

  @override
  Widget build(BuildContext context) {
    final index = IndexScope.of(context);
    final title = widget.title;
    final copies = _copies;
    final year = title.year;
    final rows = copies == null ? const <_Entry>[] : _entriesOf(title, copies);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) {
          final gutter = box.maxWidth >= 900 ? 40.0 : 20.0;
          final sides = EdgeInsets.symmetric(horizontal: gutter);
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: sides.copyWith(top: 28, bottom: 18),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: _Header(
                            title: year == null
                                ? title.name
                                : '${title.name} ($year)',
                            subtitle: copies == null
                                ? 'Reading …'
                                : copies.isEmpty
                                ? 'No video of it is on an enabled server any '
                                      'more.'
                                : title.kind == TitleKind.series
                                ? 'A tap plays an episode; the ones after it '
                                      'follow.'
                                : 'A tap plays a copy.',
                          ),
                        ),
                      ),
                      if (title.posterPath case final poster?) ...[
                        const SizedBox(width: 16),
                        TmdbPicture(
                          key: const Key('title-poster'),
                          path: poster,
                          size: 'w342',
                          width: 92,
                          height: 138,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: sides,
                sliver: SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) => switch (rows[i]) {
                    _Heading(:final text) => Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : 14, bottom: 8),
                      child: PanelHeading(text),
                    ),
                    _Copy(:final copy) => _CopyRow(
                      copy: copy,
                      isEpisode: title.kind == TitleKind.series,
                      source: _sourceOf(index, copy.sourceId),
                      playable: _isPlayable(copy, index),
                      onPlay: () => _play(copy, copies!, index),
                    ),
                  },
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

/// The episodes to play when [start] is tapped: [start] itself, then one
/// copy of each episode after it, in the order of [copies]. A copy on the
/// same server as [start] is taken if there is one. Trailers and samples
/// are left out, and so is what [playable] refuses.
List<TitleCopy> episodesFrom(
  List<TitleCopy> copies,
  TitleCopy start, {
  required bool Function(TitleCopy copy) playable,
  int limit = 50,
}) {
  final at = copies.indexOf(start);
  if (at < 0 || start.episode == null) return [start];
  final own = (start.season, start.episode);
  final next = <(int?, int?), TitleCopy>{};
  for (final copy in copies.skip(at + 1)) {
    if (copy.extra != null || copy.episode == null || !playable(copy)) continue;
    final episode = (copy.season, copy.episode);
    if (episode == own) continue;
    final chosen = next[episode];
    if (chosen == null) {
      if (next.length >= limit - 1) break;
      next[episode] = copy;
    } else if (chosen.sourceId != start.sourceId &&
        copy.sourceId == start.sourceId) {
      next[episode] = copy;
    }
  }
  return [start, ...next.values];
}

/// What the name of a copy says about it, for one line: "1080p · BluRay ·
/// HEVC · Dual Audio · Hindi, English · 3D".
String describeCopy(TitleCopy copy) {
  final height = copy.height;
  return [
    if (height != null) '${height}p',
    if (copy.source case final source?) source.label,
    if (copy.codec case final codec?) codec.label,
    if (copy.audio case final audio?) audio.label,
    if (copy.languages.isNotEmpty) copy.languages.join(', '),
    if (copy.is3d) '3D',
  ].join(' · ');
}

/// A line of the list of a title's videos.
sealed class _Entry {
  const _Entry();
}

class _Heading extends _Entry {
  const _Heading(this.text);

  final String text;
}

class _Copy extends _Entry {
  const _Copy(this.copy);

  final TitleCopy copy;
}

/// The copies with a heading wherever a new group starts. They come in
/// order: by season and episode, trailers and samples last.
List<_Entry> _entriesOf(TitleHit title, List<TitleCopy> copies) {
  final entries = <_Entry>[];
  String? group;
  for (final copy in copies) {
    final season = copy.season;
    final heading = copy.extra != null
        ? 'Trailers and samples'
        : title.kind != TitleKind.series
        ? (copies.length == 1 ? '1 copy' : 'Copies')
        : season == null
        ? 'Episodes'
        : 'Season $season';
    if (heading != group) entries.add(_Heading(group = heading));
    entries.add(_Copy(copy));
  }
  return entries;
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.copy,
    required this.isEpisode,
    required this.source,
    required this.playable,
    required this.onPlay,
  });

  final TitleCopy copy;
  final bool isEpisode;
  final Source? source;
  final bool playable;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final quality = describeCopy(copy);
    final size = copy.size;
    final part = copy.part;
    final details = [
      source?.name ?? copy.sourceId,
      if (isEpisode && quality.isNotEmpty) quality,
      if (size != null) _size(size),
      if (copy.group case final group?) group,
      if (!playable) 'cannot be played yet',
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('copy-${copy.fileId}'),
          borderRadius: BorderRadius.circular(DharaRadii.md),
          onTap: playable ? onPlay : null,
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
                        [
                          if (isEpisode)
                            _episodeLabel(copy)
                          else if (copy.extra != null)
                            copy.name
                          else
                            quality.isEmpty ? copy.name : quality,
                          if (part != null) 'CD $part',
                        ].join('  ·  '),
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

/// "Episode 2 · The Name", "Episodes 1–3"; the file name for a trailer.
String _episodeLabel(TitleCopy copy) {
  final episode = copy.episode;
  if (episode == null || copy.extra != null) return copy.name;
  final last = copy.episodeEnd;
  return [
    last == null ? 'Episode $episode' : 'Episodes $episode–$last',
    if (copy.episodeName case final name?) name,
  ].join('  ·  ');
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: DharaColors.text2,
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

Source? _sourceOf(IndexController index, String id) {
  for (final source in index.sources.sources) {
    if (source.id == id) return source;
  }
  return null;
}

/// Whether the player can open this copy: an ordinary web address, and not
/// on a media server, which wants its session token with every request
/// (the player cannot send that yet).
bool _isPlayable(TitleCopy copy, IndexController index) {
  final url = copy.url;
  final type = _sourceOf(index, copy.sourceId)?.type;
  return allowedUrlSchemes.contains(url.scheme) &&
      url.host.isNotEmpty &&
      url.userInfo.isEmpty &&
      type != SourceType.emby &&
      type != SourceType.jellyfin;
}

final _rowDecoration = BoxDecoration(
  color: DharaColors.surface,
  borderRadius: BorderRadius.circular(DharaRadii.md),
  border: Border.all(color: DharaColors.stroke),
);

/// A file size the way people say it: "1.6 GB", "700 MB".
String _size(int bytes) {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  return '${(bytes / 1024).ceil()} KB';
}
