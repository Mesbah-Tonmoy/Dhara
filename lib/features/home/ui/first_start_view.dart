import 'dart:async';

import 'package:dhara/features/indexer/crawler.dart';
import 'package:dhara/features/indexer/index_controller.dart';
import 'package:dhara/features/snapshot/first_start_controller.dart';
import 'package:dhara/features/snapshot/snapshot_controller.dart';
import 'package:dhara/features/snapshot/snapshot_fetcher.dart';
import 'package:dhara/shell/shell_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:flutter/material.dart';

/// What a production build's Home shows while the library holds nothing
/// to list: how far the first start is with making it ready, what went
/// wrong with that and what can be done, or how far a reading of the
/// servers is. With none of these to say, it is [empty].
class FirstStartView extends StatelessWidget {
  const FirstStartView({super.key, required this.empty});

  /// What to show when there is nothing to say about a first start.
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    final start = FirstStartScope.maybeOf(context);
    final index = IndexScope.of(context);
    if (start != null && start.isWorking) return _Working(start: start);
    if (index.isRunning) return _ReadingServers(index: index);
    if (start?.problem != null) return _Problem(start: start!, index: index);
    return empty;
  }
}

/// The first start under way: what it is doing and how far it is.
class _Working extends StatelessWidget {
  const _Working({required this.start});

  final FirstStartController start;

  @override
  Widget build(BuildContext context) {
    final progress = start.progress;
    final duration = motion(context, DharaMotion.base);
    return Padding(
      key: const Key('home-first-start'),
      padding: const EdgeInsets.symmetric(vertical: 4 * rem, horizontal: rem),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            DharaIcons.library,
            size: 2.6 * rem,
            color: DharaColors.text3,
          ),
          const SizedBox(height: .6 * rem),
          const Text(
            'Getting your library ready',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: DharaFonts.display,
              fontSize: DharaType.lg,
              fontWeight: DharaType.bold,
              height: DharaType.snug,
              color: DharaColors.text,
            ),
          ),
          const SizedBox(height: .5 * rem),
          Text(
            _doing(start),
            key: const Key('home-first-start-step'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: DharaFonts.ui,
              fontSize: DharaType.md,
              height: DharaType.body,
              fontFeatures: [FontFeature.tabularFigures()],
              color: DharaColors.text2,
            ),
          ),
          const SizedBox(height: rem),
          Semantics(
            label: 'Progress',
            value: progress == null ? null : '${(progress * 100).round()}%',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                width: 22 * rem,
                height: 4,
                child: ColoredBox(
                  color: DharaColors.surface2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedFractionallySizedBox(
                      duration: duration,
                      widthFactor: progress ?? 0,
                      heightFactor: 1,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: DharaColors.accentGradient,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: rem),
          const Text(
            'This is done once and takes a few minutes. Keep the window '
            'open; the films and shows appear here by themselves.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: DharaFonts.ui,
              fontSize: DharaType.sm,
              height: DharaType.body,
              color: DharaColors.text3,
            ),
          ),
        ],
      ),
    );
  }

  static String _doing(FirstStartController start) {
    switch (start.step) {
      case FirstStartStep.fetching:
        final fetched = _megabytes(start.bytesFetched);
        final expected = start.bytesExpected;
        return expected == null
            ? 'Fetching the library … $fetched MB'
            : 'Fetching the library … $fetched of ${_megabytes(expected)} MB';
      case FirstStartStep.reading:
        final progress = start.progress;
        return progress == null
            ? 'Putting the library in place …'
            : 'Putting the library in place … ${(progress * 100).floor()}%';
      case FirstStartStep.testingServers:
        return 'Finding the servers that answer from your connection …';
      case null:
        return 'Reading what is there …';
    }
  }

  static int _megabytes(int bytes) => (bytes / (1024 * 1024)).round();
}

/// The servers being read, after the user chose that over a library that
/// could not be fetched.
class _ReadingServers extends StatelessWidget {
  const _ReadingServers({required this.index});

  final IndexController index;

  @override
  Widget build(BuildContext context) {
    var videos = 0;
    for (final source in index.crawlableSources) {
      final progress = index.progressOf(source.id);
      videos += index.statsOf(source.id)?.files ?? 0;
      if (progress != null && progress.state == CrawlState.running) {
        videos += progress.filesAdded - progress.filesRemoved;
      }
    }
    return EmptyState(
      key: const Key('home-reading-servers'),
      icon: DharaIcons.servers,
      title: 'Reading the servers',
      message:
          '$videos videos found so far. A first reading takes a long '
          'while; the films and shows appear here when it is done.',
      action: DharaButton(
        key: const Key('home-reading-stop'),
        label: index.isStopping ? 'Stopping …' : 'Stop',
        icon: DharaIcons.stop,
        small: true,
        onPressed: index.isStopping ? null : index.stop,
      ),
    );
  }
}

/// The first start did not fill the library: why, and what can be done.
class _Problem extends StatelessWidget {
  const _Problem({required this.start, required this.index});

  final FirstStartController start;
  final IndexController index;

  @override
  Widget build(BuildContext context) {
    final problem = start.problem!;
    final canRetry = problem != FirstStartProblem.nothingToFetch;
    final canRead = index.crawlableSources.isNotEmpty;
    final noServer = start.serversFound == 0;
    final what = switch (problem) {
      FirstStartProblem.nothingToFetch =>
        'This copy of Dhara has no library to start from.',
      FirstStartProblem.notFetched => switch (start.fetchProblem) {
        SnapshotFetchProblem.notThere =>
          'The library is not where this copy of Dhara looks for it.',
        SnapshotFetchProblem.tooLarge =>
          'What lies where the library should be is too large to be one.',
        SnapshotFetchProblem.notSaved =>
          'The library could not be saved on this PC. Is the disk full?',
        SnapshotFetchProblem.unreachable || null =>
          'The place the library is kept did not answer. Check the '
              'internet connection and try again.',
      },
      FirstStartProblem.notRead => switch (start.readProblem) {
        final problem? => snapshotProblemText(problem),
        null => 'The library that was fetched could not be read.',
      },
    };
    final then = noServer
        ? ' None of the servers answered either: they only answer on a '
              'BDIX connection in Bangladesh.'
        : canRead
        ? ' Dhara can read the servers itself instead, which takes much '
              'longer.'
        : '';
    return EmptyState(
      key: const Key('home-first-start-problem'),
      icon: DharaIcons.library,
      title: canRetry
          ? 'The library could not be fetched'
          : 'Nothing to watch yet',
      message: '$what$then',
      action: Wrap(
        alignment: WrapAlignment.center,
        spacing: DharaSpace.s3,
        runSpacing: DharaSpace.s3,
        children: [
          if (canRetry)
            DharaButton(
              key: const Key('home-first-start-retry'),
              label: 'Try again',
              icon: DharaIcons.refresh,
              small: true,
              style: DharaButtonStyle.primary,
              autofocus: true,
              onPressed: () => unawaited(start.retry()),
            ),
          if (canRead)
            DharaButton(
              key: const Key('home-read-servers'),
              label: 'Read the servers',
              icon: DharaIcons.servers,
              small: true,
              style: canRetry
                  ? DharaButtonStyle.glass
                  : DharaButtonStyle.primary,
              // Never the button a key press lands on by itself: what it
              // starts runs for hours.
              onPressed: () => unawaited(index.start()),
            ),
          DharaButton(
            key: const Key('home-empty-servers'),
            label: 'Server Discovery',
            small: true,
            onPressed: () =>
                ShellScope.read(context).open(ShellDestination.discovery),
          ),
        ],
      ),
    );
  }
}
