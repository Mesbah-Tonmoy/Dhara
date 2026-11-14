import 'dart:async';

import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/features/metadata/review_controller.dart';
import 'package:dhara/features/metadata/review_store.dart';
import 'package:dhara/features/metadata/title_matcher.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:dhara/features/player/widgets/glass.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The titles TMDB gave no sure answer for: matched but not surely, or not
/// found. A tap on one shows what TMDB offers for it and lets the user
/// take one, search by another name, or leave the title as it is.
///
/// Names of files and folders come from the servers, titles and
/// descriptions from TMDB's users: all of it is shown through plain `Text`
/// widgets only.
class NeedsReviewScreen extends StatefulWidget {
  const NeedsReviewScreen({super.key});

  @override
  State<NeedsReviewScreen> createState() => _NeedsReviewScreenState();
}

class _NeedsReviewScreenState extends State<NeedsReviewScreen> {
  var _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    unawaited(ReviewScope.of(context).load());
  }

  @override
  Widget build(BuildContext context) {
    final review = ReviewScope.of(context);
    final items = review.items;

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                                  'Needs review',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Titles TMDB gave no sure answer for. Open '
                                  'one to pick the right film or show, or to '
                                  'leave it as its files name it. What you '
                                  'decide here is never changed by the app.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: DharaColors.text2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      PanelHeading(
                        items == null
                            ? 'Reading …'
                            : items.isEmpty
                            ? 'Nothing to review'
                            : items.length == 1
                            ? '1 title'
                            : '${items.length} titles',
                      ),
                    ],
                  ),
                ),
              ),
              if (items != null)
                SliverPadding(
                  padding: sides,
                  sliver: SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) => _ItemRow(
                      item: items[i],
                      onOpen: () => unawaited(
                        showDialog<void>(
                          context: context,
                          builder: (_) =>
                              _ReviewDialog(item: items[i], review: review),
                        ),
                      ),
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

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onOpen});

  final ReviewItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final year = item.year;
    final confidence = item.confidence;
    final where = [
      if (item.samplePath case final path? when path.isNotEmpty) path,
      ?item.sampleName,
    ].join(' / ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('review-item-${item.id}'),
          borderRadius: BorderRadius.circular(DharaRadii.md),
          onTap: onOpen,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
            decoration: BoxDecoration(
              color: DharaColors.surface,
              borderRadius: BorderRadius.circular(DharaRadii.md),
              border: Border.all(color: DharaColors.stroke),
            ),
            child: Row(
              children: [
                TmdbPicture(
                  path: item.posterPath,
                  size: 'w154',
                  width: 34,
                  height: 51,
                  placeholder: item.kind == TitleKind.series
                      ? Icons.tv_rounded
                      : Icons.movie_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        year == null ? item.name : '${item.name} ($year)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        where,
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
                const SizedBox(width: 14),
                Text(
                  item.notFound
                      ? 'Not found'
                      : confidence == null
                      ? 'Unsure'
                      : 'Unsure · $confidence',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: item.notFound ? DharaColors.text3 : DharaColors.warn,
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 70,
                  child: Text(
                    item.copies == 1 ? '1 video' : '${item.copies} videos',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: DharaColors.text2,
                    ),
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

/// Asks which film or show [item] is: what TMDB offered for it, a search
/// by another name, or "leave it as it is". Completes when it is closed.
Future<void> showReviewDialog(BuildContext context, ReviewItem item) {
  final review = ReviewScope.read(context);
  return showDialog<void>(
    context: context,
    builder: (_) => _ReviewDialog(item: item, review: review),
  );
}

/// What TMDB offers for one title, and the search by another name.
class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.item, required this.review});

  final ReviewItem item;
  final ReviewController review;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late final _name = TextEditingController(text: widget.item.spelledName);
  late final _year = TextEditingController(
    text: widget.item.spelledYear?.toString() ?? '',
  );

  /// `null` while they are being read or searched for.
  List<ScoredCandidate>? _candidates;
  String? _failure;
  var _searches = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_readKept());
  }

  @override
  void dispose() {
    _name.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _readKept() async {
    final number = ++_searches;
    final kept = await widget.review.candidatesOf(widget.item);
    if (mounted && number == _searches) setState(() => _candidates = kept);
  }

  Future<void> _search() async {
    final number = ++_searches;
    setState(() {
      _candidates = null;
      _failure = null;
    });
    final found = await widget.review.search(
      widget.item,
      _name.text,
      int.tryParse(_year.text.trim()),
    );
    // Only the answer to the latest search counts.
    if (!mounted || number != _searches) return;
    setState(() {
      _candidates = found.candidates;
      _failure = found.failure;
    });
  }

  Future<void> _choose(TmdbCandidate candidate) async {
    await widget.review.choose(widget.item, candidate);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _leave() async {
    await widget.review.leaveAsIs(widget.item);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final candidates = _candidates;
    final isShow = item.kind == TitleKind.series;
    final where = [
      if (item.samplePath case final path? when path.isNotEmpty) path,
      ?item.sampleName,
    ].join(' / ');

    return Dialog(
      backgroundColor: DharaColors.glassStrong,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isShow ? 'Which show is this?' : 'Which film is this?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                where,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: DharaColors.text3),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('review-name'),
                      controller: _name,
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) => unawaited(_search()),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Title',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      key: const Key('review-year'),
                      controller: _year,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      onSubmitted: (_) => unawaited(_search()),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Year',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  DharaPillButton(
                    key: const Key('review-search'),
                    primary: true,
                    icon: Icons.search_rounded,
                    label: 'Search TMDB',
                    onPressed: () => unawaited(_search()),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              PanelHeading(
                candidates == null
                    ? 'Asking …'
                    : _failure != null
                    ? 'No answer'
                    : candidates.isEmpty
                    ? 'TMDB knows nothing by that name'
                    : 'Pick the right one',
              ),
              if (_failure case final failure?) ...[
                const SizedBox(height: 6),
                Text(
                  failure,
                  key: const Key('review-failure'),
                  style: const TextStyle(fontSize: 13, color: DharaColors.warn),
                ),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final scored
                        in candidates ?? const <ScoredCandidate>[])
                      _CandidateRow(
                        scored: scored,
                        onChoose: () => unawaited(_choose(scored.candidate)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    key: const Key('review-leave'),
                    onPressed: () => unawaited(_leave()),
                    child: const Text('Leave it as it is'),
                  ),
                  const Spacer(),
                  TextButton(
                    key: const Key('review-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({required this.scored, required this.onChoose});

  final ScoredCandidate scored;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final candidate = scored.candidate;
    final year = candidate.year;
    final original = candidate.originalTitle;
    final sure = scored.confidence >= sureConfidence;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('review-candidate-${candidate.id}'),
          borderRadius: BorderRadius.circular(DharaRadii.md),
          onTap: onChoose,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
            decoration: BoxDecoration(
              color: DharaColors.surface,
              borderRadius: BorderRadius.circular(DharaRadii.md),
              border: Border.all(color: DharaColors.stroke),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TmdbPicture(
                  path: candidate.posterPath,
                  size: 'w154',
                  width: 50,
                  height: 75,
                  placeholder: candidate.kind == TitleKind.series
                      ? Icons.tv_rounded
                      : Icons.movie_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        year == null
                            ? candidate.title
                            : '${candidate.title} ($year)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (original != null)
                        Text(
                          original,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: DharaColors.text2,
                          ),
                        ),
                      if (candidate.overview case final overview?)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            overview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: DharaColors.text3,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${scored.confidence}',
                  style: TextStyle(
                    fontFamily: DharaFonts.display,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: sure ? DharaColors.good : DharaColors.text2,
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
