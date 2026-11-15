import 'dart:async';

import 'package:dhara/core/images/remote_image.dart';
import 'package:dhara/core/net/media_url.dart';
import 'package:dhara/features/details/ui/details_screen.dart';
import 'package:dhara/features/history/history_controller.dart';
import 'package:dhara/features/history/history_store.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/home/ui/poster_card.dart';
import 'package:dhara/features/home/ui/title_meta.dart';
import 'package:dhara/features/home/ui/wide_card.dart';
import 'package:dhara/features/metadata/titles_controller.dart';
import 'package:dhara/features/my_list/my_list_controller.dart';
import 'package:dhara/features/playback/play.dart';
import 'package:dhara/features/playback/smart_start.dart';
import 'package:dhara/shell/page_bleed.dart';
import 'package:dhara/shell/shell_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/chips.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/placeholder_art.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:dhara/widgets/toast.dart';
import 'package:flutter/material.dart';

/// The two lists the page shows.
enum ListsTab { myList, history }

/// "Today", "Yesterday", or "12 Nov 2026": the day [time] is on, seen from
/// [now].
String dayLabel(DateTime time, DateTime now) {
  final day = DateTime(time.year, time.month, time.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${time.day} ${months[time.month - 1]} ${time.year}';
}

/// "18:05".
String clockLabel(DateTime time) =>
    '${'${time.hour}'.padLeft(2, '0')}:${'${time.minute}'.padLeft(2, '0')}';

/// The prototype's My List / History screen: the titles that were saved,
/// as a grid of posters, or what was watched, day by day, each to be
/// played on from where it was left.
///
/// Both are kept in the library database on this PC only. Titles and file
/// names come from outside and are drawn as plain text.
class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key, required this.tab, this.now = DateTime.now});

  final ListsTab tab;
  final DateTime Function() now;

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  /// The cards of My List; `null` until they were read.
  List<TitleCard>? _mine;
  MyListController? _list;
  var _asked = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final list = MyListScope.read(context);
    if (list == _list) return;
    _list?.removeListener(_readMine);
    _list = list..addListener(_readMine);
    _readMine();
    if (widget.tab == ListsTab.history) {
      unawaited(HistoryScope.read(context).load());
    }
  }

  @override
  void dispose() {
    _list?.removeListener(_readMine);
    super.dispose();
  }

  /// Reads the cards of My List again: it has changed, here or elsewhere.
  Future<void> _readMine() async {
    final number = ++_asked;
    final sources = TitlesScope.read(context).index.sources;
    final cards = await _list!.cards([
      for (final source in sources.sources)
        if (sources.isEnabled(source.id)) source.id,
    ]);
    if (mounted && number == _asked) setState(() => _mine = cards);
  }

  void _show(ListsTab tab) => ShellScope.read(context).open(
    tab == ListsTab.myList ? ShellDestination.myList : ShellDestination.history,
  );

  Future<void> _play(HistoryItem item) async {
    final title = item.title;
    if (title != null) {
      await playTitleById(
        context,
        title: title.id,
        name: title.name,
        year: title.year,
        resumeUrl: item.video.url,
      );
    } else {
      // Not in the index: played from a pasted address, checked again.
      final url = parseMediaUrl(item.video.url);
      if (url == null) {
        ToastHost.show(context, 'This address cannot be played any more.');
        return;
      }
      await openPlayer(context, [PlayEntry.url(url)]);
    }
    if (mounted) await HistoryScope.read(context).load();
  }

  Future<void> _clear() => clearHistoryAfterAsking(context);

  @override
  Widget build(BuildContext context) {
    final isList = widget.tab == ListsTab.myList;
    final history = HistoryScope.of(context);
    final watched = history.items;
    final mine = _mine;
    const sides = EdgeInsets.only(
      left: PageInsets.contentLeft,
      right: DharaLayout.pageRight,
    );

    final String sub;
    if (isList) {
      sub = mine == null
          ? ''
          : '${mine.length} saved ${mine.length == 1 ? 'title' : 'titles'}';
    } else {
      sub = watched == null
          ? (history.failed ? 'The library did not answer.' : '')
          : '${watched.length} recently watched · kept on this PC only';
    }

    return ColoredBox(
      key: const Key('lists'),
      color: DharaColors.bg,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: sides.copyWith(top: 1.8 * rem, bottom: 1.4 * rem),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: rem,
                runSpacing: rem,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isList ? 'My List' : 'History',
                        key: const Key('lists-heading'),
                        style: const TextStyle(
                          fontFamily: DharaFonts.display,
                          fontSize: DharaType.xxl,
                          fontWeight: DharaType.bold,
                          letterSpacing: -.03 * DharaType.xxl,
                          height: 1.1,
                          color: DharaColors.text,
                        ),
                      ),
                      const SizedBox(height: .3 * rem),
                      Text(
                        sub,
                        key: const Key('lists-info'),
                        style: const TextStyle(
                          fontFamily: DharaFonts.ui,
                          fontSize: DharaType.sm,
                          color: DharaColors.text2,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SegmentedPills<ListsTab>(
                        key: const Key('lists-tabs'),
                        choices: const {
                          ListsTab.myList: 'My List',
                          ListsTab.history: 'History',
                        },
                        selected: widget.tab,
                        onSelected: _show,
                      ),
                      if (!isList && watched != null && watched.isNotEmpty) ...[
                        const SizedBox(width: .5 * rem),
                        DharaButton(
                          key: const Key('history-clear'),
                          label: 'Clear history',
                          icon: DharaIcons.remove,
                          small: true,
                          danger: true,
                          onPressed: () => unawaited(_clear()),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isList) ..._myList(mine, sides) else ..._history(watched, sides),
        ],
      ),
    );
  }

  List<Widget> _myList(List<TitleCard>? mine, EdgeInsets sides) {
    if (mine == null) return const [];
    if (mine.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: EmptyState(
            key: Key('my-list-empty'),
            icon: DharaIcons.myList,
            title: 'Your list is empty',
            message: 'Press “My List” on any title to keep it here.',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: sides.copyWith(bottom: DharaSpace.s7),
        sliver: SliverLayoutBuilder(
          builder: (context, box) {
            const gap = DharaLayout.cardGap;
            final columns =
                ((box.crossAxisExtent + gap) / (DharaLayout.posterWidth + gap))
                    .floor()
                    .clamp(1, 40);
            return SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: gap,
                mainAxisSpacing: 1.5 * rem,
                childAspectRatio: 2 / 3,
              ),
              itemCount: mine.length,
              itemBuilder: (context, index) => _Saved(
                key: ValueKey(mine[index].id),
                title: mine[index],
                onOpen: () => openDetails(context, mine[index]),
                onRemove: () {
                  _list!.toggle(mine[index].id);
                  ToastHost.show(
                    context,
                    'was taken off My List.',
                    lead: mine[index].name,
                  );
                },
              ),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _history(List<HistoryItem>? watched, EdgeInsets sides) {
    if (watched == null) return const [];
    if (watched.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: EmptyState(
            key: Key('history-empty'),
            icon: DharaIcons.history,
            title: 'No history yet',
            message:
                'What you watch shows up here, so that you can go on with '
                'it.',
          ),
        ),
      ];
    }
    final now = widget.now();
    final sources = TitlesScope.read(context).index.sources;
    // The lines, with the day above the first video of each day.
    final lines = <Object>[];
    String? day;
    for (final item in watched) {
      final label = dayLabel(item.video.watchedAt, now);
      if (label != day) lines.add(day = label);
      lines.add(item);
    }
    return [
      SliverPadding(
        padding: sides.copyWith(bottom: DharaSpace.s7),
        sliver: SliverList.builder(
          itemCount: lines.length,
          itemBuilder: (context, index) => switch (lines[index]) {
            final String label => Padding(
              padding: EdgeInsets.only(
                top: index == 0 ? 0 : 1.2 * rem,
                bottom: .5 * rem,
                left: .55 * rem,
              ),
              child: Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontFamily: DharaFonts.ui,
                  fontSize: DharaType.xs,
                  fontWeight: DharaType.semibold,
                  letterSpacing: .12 * DharaType.xs,
                  color: DharaColors.text3,
                ),
              ),
            ),
            final HistoryItem item => Padding(
              padding: const EdgeInsets.only(bottom: .3 * rem),
              child: _Watched(
                key: ValueKey(item.video.url),
                item: item,
                server: switch (item.sourceId) {
                  null => null,
                  final id =>
                    sources.sources
                        .where((source) => source.id == id)
                        .firstOrNull
                        ?.name,
                },
                onPlay: () => unawaited(_play(item)),
                onRemove: () {
                  unawaited(HistoryScope.read(context).remove(item));
                  ToastHost.show(context, 'Removed from the history.');
                },
              ),
            ),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    ];
  }
}

/// A poster on My List: as anywhere, with a round button in its corner
/// that takes it off the list (the prototype's `.unlist`).
class _Saved extends StatefulWidget {
  const _Saved({
    super.key,
    required this.title,
    required this.onOpen,
    required this.onRemove,
  });

  final TitleCard title;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  State<_Saved> createState() => _SavedState();
}

class _SavedState extends State<_Saved> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: PosterCard(title: widget.title, onOpen: widget.onOpen),
        ),
        Positioned(
          top: .45 * rem,
          right: .45 * rem,
          child: Pressable(
            key: Key('unlist-${widget.title.id}'),
            onPressed: widget.onRemove,
            tooltip: 'Take off My List',
            semanticLabel: 'Take ${widget.title.name} off My List',
            builder: (context, state) => AnimatedOpacity(
              // Shown to the pointer over the card, and to the keyboard.
              opacity: _hovered || state.focused ? 1 : 0,
              duration: motion(context, DharaMotion.fast),
              child: Container(
                width: 1.8 * rem,
                height: 1.8 * rem,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state.hovered
                      ? DharaColors.bad
                      : const Color(0xD90A0C16),
                  border: Border.all(color: DharaColors.strokeStrong),
                ),
                child: const Icon(
                  DharaIcons.close,
                  size: .95 * rem,
                  color: DharaColors.text,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The prototype's `.hist`: one video that was watched, with its picture
/// and how far it got; a click plays it on.
class _Watched extends StatelessWidget {
  const _Watched({
    super.key,
    required this.item,
    required this.server,
    required this.onPlay,
    required this.onRemove,
  });

  final HistoryItem item;

  /// The name of the server it is on, if that is known.
  final String? server;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final video = item.video;
    final title = item.title;
    final episode = item.episode;
    final url = Uri.tryParse(video.url);
    final name =
        title?.name ??
        item.fileName ??
        (url == null ? video.url : mediaTitleFromUrl(url));
    final sub = episode != null
        ? [
            episodeCode(item.season, episode),
            if (item.episodeName case final called?) called,
          ].join(' · ')
        : [
            if (title?.year case final year?) '$year',
            if (title?.runtime case final minutes? when minutes > 0)
              runtimeLabel(minutes),
            if (title == null) 'Not in the library',
          ].join(' · ');
    final meta = [
      clockLabel(video.watchedAt),
      if (server != null) 'via $server',
      if (video.finished)
        'Finished'
      else
        timeLeftLabel(video.duration - video.position),
    ].join(' · ');
    final progress = video.finished || video.duration <= Duration.zero
        ? (video.finished ? 1.0 : 0.0)
        : (video.position.inMilliseconds / video.duration.inMilliseconds).clamp(
            0.0,
            1.0,
          );
    final radius = BorderRadius.circular(DharaRadii.md);

    return Pressable(
      onPressed: onPlay,
      semanticLabel: '$name, $sub, $meta',
      builder: (context, state) => FocusRing(
        visible: state.focused,
        radius: radius,
        child: AnimatedContainer(
          duration: motion(context, DharaMotion.fast),
          padding: const EdgeInsets.fromLTRB(
            .55 * rem,
            .55 * rem,
            .9 * rem,
            .55 * rem,
          ),
          decoration: BoxDecoration(
            color: state.active ? DharaColors.surface : null,
            borderRadius: radius,
            border: Border.all(
              color: state.active
                  ? DharaColors.stroke
                  : const Color(0x00FFFFFF),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 12 * rem,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(DharaRadii.sm),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        TmdbCover(
                          path: item.stillPath ?? title?.backdropPath,
                          size: 'w300',
                          placeholder: PlaceholderArt(seed: name, wide: true),
                        ),
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: WatchedBar(progress: progress),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 1.2 * rem),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: DharaFonts.ui,
                          fontSize: DharaType.md,
                          fontWeight: DharaType.semibold,
                          height: 1.4,
                          color: DharaColors.text,
                        ),
                      ),
                      if (sub.isNotEmpty)
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: DharaFonts.ui,
                            fontSize: DharaType.sm,
                            height: 1.4,
                            color: DharaColors.text2,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: .2 * rem),
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: DharaFonts.ui,
                            fontSize: DharaType.xs,
                            color: DharaColors.text3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: .5 * rem),
              DharaButton(
                label: video.finished ? 'Watch again' : 'Resume',
                icon: DharaIcons.play,
                small: true,
                style: video.finished
                    ? DharaButtonStyle.glass
                    : DharaButtonStyle.primary,
                onPressed: onPlay,
              ),
              const SizedBox(width: .5 * rem),
              DharaIconButton(
                icon: DharaIcons.remove,
                label: 'Remove from the history',
                onPressed: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks whether the whole history may go and, on a yes, empties it (and
/// forgets where every video was left).
Future<void> clearHistoryAfterAsking(BuildContext context) async {
  final history = HistoryScope.read(context);
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Clear the history?'),
      content: const Text(
        'Everything in History goes, and so do the places where videos '
        'were left: nothing will be offered to continue. This cannot be '
        'undone.',
      ),
      actions: [
        DharaButton(
          key: const Key('history-clear-cancel'),
          label: 'Cancel',
          small: true,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        DharaButton(
          key: const Key('history-clear-confirm'),
          label: 'Clear history',
          small: true,
          danger: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  if (sure != true) return;
  await history.clear();
  if (context.mounted) ToastHost.show(context, 'History cleared.');
}
