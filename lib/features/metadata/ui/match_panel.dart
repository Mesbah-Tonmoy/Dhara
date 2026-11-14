import 'dart:async';

import 'package:dhara/features/metadata/match_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/player/widgets/glass.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// How many titles TMDB has been asked about and with what result, and the
/// button that starts or stops asking.
class MatchPanel extends StatelessWidget {
  const MatchPanel({super.key, required this.match, required this.tmdbKey});

  final MatchController match;
  final TmdbKeyController tmdbKey;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([match, tmdbKey]),
      builder: (context, _) {
        final counts = match.counts;
        final running = match.isRunning;
        final (status, color) = _status();
        final canStart = tmdbKey.hasKey && (counts?.pending ?? 0) > 0;

        return Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: BoxDecoration(
            color: DharaColors.surface,
            borderRadius: BorderRadius.circular(DharaRadii.md),
            border: Border.all(color: DharaColors.stroke),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PanelHeading('Posters and descriptions (TMDB)'),
                    const SizedBox(height: 6),
                    Text(
                      counts == null
                          ? 'Counting …'
                          : '${counts.matched + counts.byHand} matched  ·  '
                                '${counts.unsure} unsure  ·  '
                                '${counts.notFound} not found  ·  '
                                '${counts.pending} not looked up yet',
                      key: const Key('match-counts'),
                      style: const TextStyle(fontSize: 13.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status,
                      key: const Key('match-status'),
                      style: TextStyle(fontSize: 12.5, color: color),
                    ),
                  ],
                ),
              ),
              if (running || canStart) ...[
                const SizedBox(width: 14),
                DharaPillButton(
                  key: const Key('match-start-stop'),
                  primary: !running,
                  icon: running
                      ? Icons.stop_rounded
                      : Icons.travel_explore_rounded,
                  label: !running
                      ? 'Match now'
                      : match.isStopping
                      ? 'Stopping …'
                      : 'Stop',
                  onPressed: running
                      ? match.stop
                      : () => unawaited(match.start()),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// What to say below the numbers, and in which colour.
  (String, Color) _status() {
    final progress = match.progress;
    if (match.isRunning) {
      return (
        progress == null || progress.total == 0
            ? 'Asking TMDB …'
            : 'Asking TMDB … ${progress.done} / ${progress.total} titles',
        DharaColors.accent2,
      );
    }
    switch (match.lastEnd) {
      case MatchEnd.keyRefused:
        return (
          'TMDB does not accept the key. Check it under "TMDB key".',
          DharaColors.bad,
        );
      case MatchEnd.unreachable:
        return (
          'TMDB could not be reached. What was matched is kept; try again '
              'later.',
          DharaColors.warn,
        );
      case MatchEnd.failed:
        return (
          'Matching stopped because of an error in the app.',
          DharaColors.warn,
        );
      case MatchEnd.stopped:
        return ('Stopped. It carries on from here.', DharaColors.text2);
      case MatchEnd.finished:
        return ('Every title has been looked up.', DharaColors.good);
      case MatchEnd.noKey || null:
        break;
    }
    if (!tmdbKey.hasKey) {
      return (
        'Add a TMDB key to get posters and descriptions. Everything else '
            'works without one.',
        DharaColors.text2,
      );
    }
    final pending = match.counts?.pending ?? 0;
    return (
      pending == 0
          ? 'Nothing to look up.'
          : 'Looking everything up takes a while the first time; it can be '
                'stopped and carried on later.',
      DharaColors.text2,
    );
  }
}
