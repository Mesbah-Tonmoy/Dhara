import 'dart:async';
import 'dart:ui';

import 'package:dhara/features/details/details_store.dart';
import 'package:dhara/features/details/ui/copies_table.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/playback/copy_choice.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:flutter/material.dart';

/// Opens the prototype's side sheet with the copies of one episode: a
/// glass panel that slides in from the right, over a dimmed window.
///
/// Completes with the copy the user chose to play, or `null` if the sheet
/// was closed (the dimmed part, the close button or Esc). [copies] are all
/// the copies of that episode; they are listed best first and follow the
/// server tests while the sheet is open.
Future<TitleCopy?> showCopiesSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<TitleCopy> copies,
  Map<String, Watched> watched = const {},
}) => showGeneralDialog<TitleCopy>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  barrierColor: const Color(0x99030408),
  transitionDuration: motion(context, DharaMotion.slow),
  pageBuilder: (context, _, _) => _CopiesSheet(
    title: title,
    subtitle: subtitle,
    copies: copies,
    watched: watched,
  ),
  transitionBuilder: (context, animation, _, child) => SlideTransition(
    position: Tween(begin: const Offset(1.03, 0), end: Offset.zero).animate(
      CurvedAnimation(
        parent: animation,
        curve: DharaMotion.easeOut,
        reverseCurve: Curves.easeIn,
      ),
    ),
    child: child,
  ),
);

class _CopiesSheet extends StatelessWidget {
  const _CopiesSheet({
    required this.title,
    required this.subtitle,
    required this.copies,
    required this.watched,
  });

  final String title;
  final String subtitle;
  final List<TitleCopy> copies;
  final Map<String, Watched> watched;

  @override
  Widget build(BuildContext context) {
    // Follows a server test that ends while the sheet is open.
    final tests = SourcesScope.of(context);
    final sources = tests.store;
    final window = MediaQuery.sizeOf(context);
    const corner = Radius.circular(DharaRadii.lg);
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(top: DharaLayout.titleBarHeight),
        child: SizedBox(
          key: const Key('copies-sheet'),
          width: (window.width * .94).clamp(0, 60 * rem).toDouble(),
          height: double.infinity,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(topLeft: corner),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 2 * rem, sigmaY: 2 * rem),
              child: Material(
                type: MaterialType.transparency,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: DharaColors.glassStrong,
                    borderRadius: BorderRadius.only(topLeft: corner),
                    border: Border(
                      top: BorderSide(color: DharaColors.strokeStrong),
                      left: BorderSide(color: DharaColors.strokeStrong),
                    ),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      1.4 * rem,
                      1.2 * rem,
                      1.4 * rem,
                      1.4 * rem,
                    ),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: DharaFonts.display,
                                    fontSize: DharaType.xl,
                                    fontWeight: DharaType.bold,
                                    height: 1.2,
                                    color: DharaColors.text,
                                  ),
                                ),
                                Text(
                                  subtitle,
                                  key: const Key('copies-sheet-subtitle'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: DharaFonts.ui,
                                    fontSize: DharaType.sm,
                                    height: DharaType.body,
                                    color: DharaColors.text2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: rem),
                          DharaButton(
                            key: const Key('copies-sheet-retest'),
                            label: tests.isTesting
                                ? 'Testing …'
                                : 'Re-test servers',
                            icon: DharaIcons.refresh,
                            small: true,
                            onPressed: tests.isTesting
                                ? null
                                : () => unawaited(
                                    tests.test([
                                      for (final source in sources.sources)
                                        if (copies.any(
                                          (copy) => copy.sourceId == source.id,
                                        ))
                                          source,
                                    ]),
                                  ),
                          ),
                          const SizedBox(width: .5 * rem),
                          DharaIconButton(
                            key: const Key('copies-sheet-close'),
                            icon: DharaIcons.close,
                            label: 'Close',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1.1 * rem),
                      CopiesTable(
                        copies: rankCopies(copies, sources),
                        sources: sources,
                        watched: watched,
                        onPlay: (copy) => Navigator.of(context).pop(copy),
                      ),
                      const SizedBox(height: rem),
                      const Text(
                        'Play on the episode itself takes the first copy '
                        'listed here: a server that answered its last test, '
                        'then the sharpest picture. Pick a row to play '
                        'another one; the episodes after it follow from the '
                        'same server where it has them.',
                        style: TextStyle(
                          fontFamily: DharaFonts.ui,
                          fontSize: DharaType.sm,
                          height: DharaType.body,
                          color: DharaColors.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
