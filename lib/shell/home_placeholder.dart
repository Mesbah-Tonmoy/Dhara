import 'dart:async';

import 'package:dhara/features/player/open_url_dialog.dart';
import 'package:dhara/shell/shell_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/logo.dart';
import 'package:flutter/material.dart';

/// What Home shows until the real Home screen (banner and rows) is built
/// in the next increments of Phase 6: the way to everything that works
/// today.
class HomePlaceholder extends StatelessWidget {
  const HomePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DharaSpace.s6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 34 * rem),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DharaLogo(size: 4 * rem),
                const SizedBox(height: DharaSpace.s4),
                const Text(
                  'Dhara',
                  key: Key('app-title'),
                  style: TextStyle(
                    fontFamily: DharaFonts.display,
                    fontSize: DharaType.xxl,
                    fontWeight: DharaType.bold,
                    letterSpacing: -.03 * DharaType.xxl,
                    height: 1.1,
                    color: DharaColors.text,
                  ),
                ),
                const SizedBox(height: DharaSpace.s2),
                const Text(
                  'The Home screen is being built. Until it is here, search '
                  'your library from the bar above, or open a part of the '
                  'app from the rail on the left.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: DharaType.md,
                    height: DharaType.body,
                    color: DharaColors.text2,
                  ),
                ),
                const SizedBox(height: DharaSpace.s5),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: DharaSpace.s3,
                  runSpacing: DharaSpace.s3,
                  children: [
                    DharaButton(
                      key: const Key('home-titles'),
                      label: 'Films and shows',
                      icon: DharaIcons.movies,
                      style: DharaButtonStyle.primary,
                      autofocus: true,
                      onPressed: () => shell.open(ShellDestination.titles),
                    ),
                    DharaButton(
                      key: const Key('home-open-url'),
                      label: 'Play a URL',
                      icon: DharaIcons.link,
                      tooltip: 'Ctrl+O',
                      onPressed: () => unawaited(showOpenUrlDialog(context)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
