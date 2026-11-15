import 'dart:async';

import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/features/metadata/review_controller.dart';
import 'package:dhara/features/metadata/review_store.dart';
import 'package:dhara/features/metadata/title_matcher.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:dhara/features/metadata/video_identity.dart';
import 'package:dhara/shell/page_bleed.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/page_parts.dart';
import 'package:dhara/widgets/surfaces.dart';
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
    const sides = EdgeInsets.only(
      left: PageInsets.contentLeft,
      right: DharaLayout.pageRight,
    );

    return ColoredBox(
      key: const Key('needs-review'),
      color: DharaColors.bg,
      // The dialog opened from here, and its fields, are Material's.
      child: Material(
        type: MaterialType.transparency,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: sides.copyWith(top: 1.8 * rem, bottom: .6 * rem),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PageHead(
                      title: 'Needs review',
                      subtitle:
                          'Titles TMDB gave no sure answer for. Open one to '
                          'pick the right film or show, or to leave it as '
                          'its files name it. What you decide here is never '
                          'changed by the app.',
                    ),
                    const SizedBox(height: 1.4 * rem),
                    CapsLabel(
                      items == null
                          ? 'Reading …'
                          : items.isEmpty
                          ? 'Nothing to review'
                          : review.total == 1
                          ? '1 title'
                          // All of them are counted, though the list is
                          // read a part at a time.
                          : review.hasMore
                          ? '${review.total} titles · the first '
                                '${items.length} listed'
                          : '${review.total} titles',
                      key: const Key('review-count'),
                    ),
                  ],
                ),
              ),
            ),
            if (items != null && items.isEmpty)
              const SliverPadding(
                padding: sides,
                sliver: SliverToBoxAdapter(
                  child: EmptyState(
                    icon: DharaIcons.check,
                    title: 'All sorted',
                    message:
                        'Every title is either matched or left as you '
                        'decided.',
                  ),
                ),
              ),
            if (items != null)
              SliverPadding(
                padding: sides,
                sliver: SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    // Near the end of what was read: the next part is
                    // read, so that scrolling goes on.
                    if (i >= items.length - 10 && review.hasMore) {
                      unawaited(review.loadMore());
                    }
                    return _ItemRow(
                      key: Key('review-item-${items[i].id}'),
                      item: items[i],
                      onOpen: () => unawaited(
                        showDialog<void>(
                          context: context,
                          builder: (_) =>
                              _ReviewDialog(item: items[i], review: review),
                        ),
                      ),
                    );
                  },
                ),
              ),
            // For the keyboard, and in case reading the next part failed.
            if (items != null && review.hasMore)
              SliverPadding(
                padding: sides.copyWith(top: rem),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${items.length} of ${review.total} titles are '
                          'listed.',
                          style: const TextStyle(
                            fontFamily: DharaFonts.ui,
                            fontSize: DharaType.sm,
                            color: DharaColors.text2,
                          ),
                        ),
                      ),
                      DharaButton(
                        key: const Key('review-more'),
                        label: 'Show more',
                        small: true,
                        onPressed: () => unawaited(review.loadMore()),
                      ),
                    ],
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: DharaSpace.s7)),
          ],
        ),
      ),
    );
  }
}

const _nameStyle = TextStyle(
  fontFamily: DharaFonts.ui,
  fontSize: DharaType.md,
  fontWeight: DharaType.semibold,
  color: DharaColors.text,
);

const _smallStyle = TextStyle(
  fontFamily: DharaFonts.ui,
  fontSize: DharaType.xs,
  height: 1.4,
  color: DharaColors.text3,
);

class _ItemRow extends StatelessWidget {
  const _ItemRow({super.key, required this.item, required this.onOpen});

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

    return RowCard(
      onPressed: onOpen,
      padding: const EdgeInsets.fromLTRB(.7 * rem, .5 * rem, rem, .5 * rem),
      child: Row(
        children: [
          TmdbPicture(
            path: item.posterPath,
            size: 'w154',
            width: 2.3 * rem,
            height: 3.45 * rem,
            placeholder: item.kind == TitleKind.series
                ? DharaIcons.series
                : DharaIcons.movies,
          ),
          const SizedBox(width: .8 * rem),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  year == null ? item.name : '${item.name} ($year)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _nameStyle,
                ),
                Text(
                  where,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _smallStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: rem),
          Text(
            item.notFound
                ? 'Not found'
                : confidence == null
                ? 'Unsure'
                : 'Unsure · $confidence',
            style: TextStyle(
              fontFamily: DharaFonts.ui,
              fontSize: DharaType.sm,
              fontWeight: DharaType.semibold,
              color: item.notFound ? DharaColors.text3 : DharaColors.warn,
            ),
          ),
          const SizedBox(width: rem),
          SizedBox(
            width: 5 * rem,
            child: Text(
              item.copies == 1 ? '1 video' : '${item.copies} videos',
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontFamily: DharaFonts.ui,
                fontSize: DharaType.sm,
                color: DharaColors.text2,
              ),
            ),
          ),
          const SizedBox(width: .3 * rem),
          const Icon(
            DharaIcons.right,
            size: 1.3 * rem,
            color: DharaColors.text3,
          ),
        ],
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

    return DharaDialog(
      maxWidth: 45 * rem,
      maxHeight: 48 * rem,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          1.4 * rem,
          1.3 * rem,
          1.4 * rem,
          rem,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isShow ? 'Which show is this?' : 'Which film is this?',
              style: const TextStyle(
                fontFamily: DharaFonts.display,
                fontSize: DharaType.xl,
                fontWeight: DharaType.bold,
                height: 1.2,
                color: DharaColors.text,
              ),
            ),
            const SizedBox(height: .3 * rem),
            Text(
              where,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _smallStyle,
            ),
            const SizedBox(height: rem),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: DharaField(
                    key: const Key('review-name'),
                    controller: _name,
                    label: 'Title',
                    autofocus: true,
                    onSubmitted: (_) => unawaited(_search()),
                  ),
                ),
                const SizedBox(width: .6 * rem),
                SizedBox(
                  width: 6 * rem,
                  child: DharaField(
                    key: const Key('review-year'),
                    controller: _year,
                    label: 'Year',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    onSubmitted: (_) => unawaited(_search()),
                  ),
                ),
                const SizedBox(width: .6 * rem),
                DharaButton(
                  key: const Key('review-search'),
                  style: DharaButtonStyle.primary,
                  small: true,
                  icon: DharaIcons.search,
                  label: 'Search TMDB',
                  onPressed: () => unawaited(_search()),
                ),
              ],
            ),
            const SizedBox(height: rem),
            CapsLabel(
              candidates == null
                  ? 'Asking …'
                  : _failure != null
                  ? 'No answer'
                  : candidates.isEmpty
                  ? 'TMDB knows nothing by that name'
                  : 'Pick the right one',
            ),
            if (_failure case final failure?) ...[
              const SizedBox(height: .4 * rem),
              Text(
                failure,
                key: const Key('review-failure'),
                style: const TextStyle(
                  fontFamily: DharaFonts.ui,
                  fontSize: DharaType.sm,
                  height: 1.4,
                  color: DharaColors.warn,
                ),
              ),
            ],
            const SizedBox(height: .6 * rem),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                // Room for the outline of the row that holds the keyboard.
                padding: const EdgeInsets.all(.3 * rem),
                children: [
                  for (final scored in candidates ?? const <ScoredCandidate>[])
                    _CandidateRow(
                      key: Key('review-candidate-${scored.candidate.id}'),
                      scored: scored,
                      onChoose: () => unawaited(_choose(scored.candidate)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: .6 * rem),
            Row(
              children: [
                DharaButton(
                  key: const Key('review-leave'),
                  label: 'Leave it as it is',
                  small: true,
                  tooltip:
                      'Keeps the title as its files name it; it is not '
                      'asked about again',
                  onPressed: () => unawaited(_leave()),
                ),
                const Spacer(),
                DharaButton(
                  key: const Key('review-close'),
                  label: 'Close',
                  small: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    super.key,
    required this.scored,
    required this.onChoose,
  });

  final ScoredCandidate scored;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final candidate = scored.candidate;
    final year = candidate.year;
    final original = candidate.originalTitle;
    final sure = scored.confidence >= sureConfidence;

    return RowCard(
      onPressed: onChoose,
      padding: const EdgeInsets.fromLTRB(
        .6 * rem,
        .5 * rem,
        .9 * rem,
        .5 * rem,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TmdbPicture(
            path: candidate.posterPath,
            size: 'w154',
            width: 3.3 * rem,
            height: 4.95 * rem,
            placeholder: candidate.kind == TitleKind.series
                ? DharaIcons.series
                : DharaIcons.movies,
          ),
          const SizedBox(width: .8 * rem),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  year == null ? candidate.title : '${candidate.title} ($year)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _nameStyle,
                ),
                if (original != null)
                  Text(
                    original,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _smallStyle.copyWith(color: DharaColors.text2),
                  ),
                if (candidate.overview case final overview?)
                  Padding(
                    padding: const EdgeInsets.only(top: .15 * rem),
                    child: Text(
                      overview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _smallStyle,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: .8 * rem),
          Tooltip(
            message: 'How well it fits, out of 100',
            child: Text(
              '${scored.confidence}',
              style: TextStyle(
                fontFamily: DharaFonts.display,
                fontSize: DharaType.lg,
                fontWeight: DharaType.bold,
                color: sure ? DharaColors.good : DharaColors.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
