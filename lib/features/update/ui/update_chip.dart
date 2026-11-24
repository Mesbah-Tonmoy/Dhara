import 'dart:async';

import 'package:dhara/features/update/ui/update_dialog.dart';
import 'package:dhara/features/update/update_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:flutter/material.dart';

/// A small pill in the title bar that says a newer version of the app
/// exists, and opens the dialog that tells more. It is not there while
/// none is known, nor in a build that does not ask.
///
/// A click fetches nothing: the dialog says what would happen first.
class UpdateChip extends StatelessWidget {
  const UpdateChip({super.key});

  @override
  Widget build(BuildContext context) {
    final notice = UpdateScope.maybeOf(context)?.available;
    if (notice == null) return const SizedBox.shrink();

    final radius = BorderRadius.circular(DharaRadii.pill);
    return Padding(
      padding: const EdgeInsets.only(left: DharaSpace.s2),
      child: Pressable(
        key: const Key('shell-update'),
        onPressed: () => unawaited(showUpdateDialog(context)),
        tooltip: 'Version ${notice.version} of Dhara is available',
        builder: (context, state) => FocusRing(
          visible: state.focused,
          radius: radius,
          child: AnimatedContainer(
            duration: motion(context, DharaMotion.fast),
            padding: const EdgeInsets.symmetric(
              horizontal: .65 * rem,
              vertical: .25 * rem,
            ),
            decoration: BoxDecoration(
              borderRadius: radius,
              color: state.hovered ? DharaColors.surface2 : DharaColors.surface,
              border: Border.all(color: DharaColors.accent2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: .45 * rem,
                  height: .45 * rem,
                  decoration: const BoxDecoration(
                    color: DharaColors.accent2,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: .45 * rem),
                const Text(
                  'Update',
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: DharaFonts.ui,
                    fontSize: DharaType.xs,
                    fontWeight: DharaType.medium,
                    height: 1.3,
                    color: DharaColors.text,
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
