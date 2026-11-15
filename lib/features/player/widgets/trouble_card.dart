import 'package:dhara/features/player/stall_watch.dart';
import 'package:dhara/features/player/widgets/glass.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Says what is wrong with a video that does not play on, and offers what
/// can be done: another copy of it (where it has one), or the same again.
class TroubleCard extends StatelessWidget {
  const TroubleCard({
    super.key,
    required this.trouble,
    required this.onRetry,
    this.onOther,
  });

  final Trouble trouble;
  final VoidCallback onRetry;

  /// `null` where the video has no other copy.
  final VoidCallback? onOther;

  @override
  Widget build(BuildContext context) {
    final onOther = this.onOther;
    return GlassPanel(
      key: const Key('trouble-card'),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            trouble.message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: DharaFonts.ui,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: DharaColors.text,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onOther != null) ...[
                DharaPillButton(
                  key: const Key('trouble-other'),
                  label: 'Try another copy',
                  primary: true,
                  onPressed: onOther,
                ),
                const SizedBox(width: 8),
              ],
              DharaPillButton(
                key: const Key('trouble-retry'),
                label: 'Try again',
                primary: onOther == null,
                onPressed: onRetry,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
