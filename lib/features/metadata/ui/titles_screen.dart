import 'dart:async';

import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/features/details/ui/details_screen.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/match_store.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/metadata/ui/match_panel.dart';
import 'package:dhara/features/metadata/ui/needs_review_screen.dart';
import 'package:dhara/features/metadata/ui/tmdb_key_card.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:dhara/features/player/widgets/glass.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// The films and shows the indexed videos are copies of: how many there
/// are, and a search by title.
///
/// A working screen until the real Home and Search screens arrive in
/// Phase 6. Titles, file names and folder paths come from the servers and
/// are shown through plain `Text` widgets only.
class TitlesScreen extends StatefulWidget {
  const TitlesScreen({super.key, this.initialQuery});

  /// What to search for as soon as the screen opens: what was typed into
  /// the search field of the title bar.
  final String? initialQuery;

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
    final first = _titles == null;
    _titles = titles..addListener(_onTitlesChanged);
    _wasReading = titles.isReading;
    final query = widget.initialQuery;
    if (first && query != null && query.trim().isNotEmpty) {
      _query.text = query;
      unawaited(_search(query));
    }
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

  void _open(TitleHit hit) => openDetails(
    context,
    TitleCard(
      id: hit.id,
      kind: hit.kind,
      name: hit.name,
      year: hit.year,
      posterPath: hit.posterPath,
      videos: hit.copies,
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

final _rowDecoration = BoxDecoration(
  color: DharaColors.surface,
  borderRadius: BorderRadius.circular(DharaRadii.md),
  border: Border.all(color: DharaColors.stroke),
);

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
