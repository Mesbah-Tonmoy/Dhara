import 'dart:async';

import 'package:dhara/core/window/window_controller.dart';
import 'package:dhara/features/update/update_controller.dart';
import 'package:dhara/features/update/update_words.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:flutter/material.dart';

/// Opens the dialog about the newer version there is: what it is, what
/// installing it does, and the button that does it. Opening it fetches
/// nothing.
Future<void> showUpdateDialog(BuildContext context) => showDialog<void>(
  context: context,
  // Esc and a click beside it close it, but not while it works: the
  // dialog itself refuses to go then.
  builder: (context) => const UpdateDialog(),
);

/// Says that a newer version exists and, on **Download and install**,
/// fetches its installer, checks it and starts it, showing how far that
/// is. When the installer is open, it closes the app.
///
/// What the notice says of the version (its notes) is shown as plain text.
class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  static const _body = TextStyle(
    fontFamily: DharaFonts.ui,
    fontSize: DharaType.sm,
    height: 1.45,
    color: DharaColors.text2,
  );

  @override
  Widget build(BuildContext context) {
    final updates = UpdateScope.maybeOf(context);
    final notice = updates?.available;
    final window = WindowScope.maybeOf(context);

    Widget later(String label) => DharaButton(
      key: const Key('update-later'),
      label: label,
      small: true,
      autofocus: true,
      onPressed: () => Navigator.of(context).pop(),
    );

    if (updates == null || notice == null) {
      return AlertDialog(
        title: const Text('Dhara is up to date'),
        content: const Text('No newer version is known.', style: _body),
        actions: [later('Close')],
      );
    }

    final step = updates.step;
    final busy = updates.isInstalling;
    final problem = updates.installerProblem;

    final List<Widget> state;
    final List<Widget> actions;
    if (updates.installerStarted) {
      state = const [
        Text(
          'The installer is open. Dhara closes now, so that it can be '
          'replaced.',
          key: Key('update-started'),
          style: _body,
        ),
      ];
      actions = [
        DharaButton(
          key: const Key('update-close-app'),
          label: 'Close Dhara',
          small: true,
          autofocus: true,
          onPressed: () => window?.close(),
        ),
      ];
    } else if (busy) {
      final fetching = step == UpdateStep.fetching;
      state = [
        ClipRRect(
          borderRadius: BorderRadius.circular(DharaRadii.pill),
          child: LinearProgressIndicator(
            key: const Key('update-progress'),
            // Never one that runs by itself: it stands still between two
            // reports.
            value: fetching
                ? (updates.bytesFetched / notice.size).clamp(0, 1).toDouble()
                : 1,
            minHeight: .35 * rem,
            color: DharaColors.accent2,
            backgroundColor: DharaColors.strokeStrong,
          ),
        ),
        const SizedBox(height: .6 * rem),
        Text(
          switch (step) {
            UpdateStep.checking =>
              'Checking that it is the installer its maker signed…',
            UpdateStep.starting => 'Starting the installer…',
            _ =>
              'Fetching the installer: ${megabytes(updates.bytesFetched)} '
                  'of ${megabytes(notice.size)}',
          },
          key: const Key('update-step'),
          style: _body.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ];
      actions = [
        if (fetching)
          DharaButton(
            key: const Key('update-stop'),
            label: 'Stop',
            small: true,
            onPressed: updates.stopFetching,
          ),
      ];
    } else if (!updates.canInstall) {
      state = const [
        Text(
          'This copy cannot fetch the installer itself. Get it from '
          'whoever gave you Dhara, and run it.',
          style: _body,
        ),
      ];
      actions = [later('Close')];
    } else {
      state = [
        if (problem != null) ...[
          Text(
            installerProblemWords(problem),
            key: const Key('update-problem'),
            style: _body.copyWith(color: DharaColors.bad),
          ),
          const SizedBox(height: .6 * rem),
        ],
        const Text(
          'Dhara fetches the installer, checks that it is the very file '
          'its maker signed, and starts it. Dhara then closes, and the '
          'installer shows what it does, as it did the first time. Your '
          'library and settings stay.',
          style: _body,
        ),
      ];
      actions = [
        later('Later'),
        DharaButton(
          key: const Key('update-install'),
          label: problem == null ? 'Download and install' : 'Try again',
          icon: DharaIcons.update,
          small: true,
          style: DharaButtonStyle.primary,
          onPressed: () => unawaited(_install(updates, window)),
        ),
      ];
    }

    return PopScope(
      // Neither Esc nor a click beside the dialog leaves a fetch running
      // behind a closed dialog.
      canPop: !busy,
      child: AlertDialog(
        title: Text(
          'Dhara ${notice.version} is available',
          key: const Key('update-title'),
        ),
        content: SizedBox(
          width: 30 * rem,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This copy is ${updates.current}. The installer is '
                '${megabytes(notice.size)}.',
                style: _body,
              ),
              if (notice.notes.isNotEmpty) ...[
                const SizedBox(height: .8 * rem),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 9 * rem),
                  child: SingleChildScrollView(
                    child: Text(
                      notice.notes,
                      key: const Key('update-notes'),
                      style: _body.copyWith(color: DharaColors.text),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: .9 * rem),
              ...state,
            ],
          ),
        ),
        actions: actions,
      ),
    );
  }

  /// Fetches, checks and starts the installer; once it is open, closes
  /// the app, whose files it is about to replace.
  static Future<void> _install(
    UpdateController updates,
    WindowController? window,
  ) async {
    if (await updates.install()) window?.close();
  }
}
