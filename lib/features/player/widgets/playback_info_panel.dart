import 'package:dhara/features/player/playback_info.dart';
import 'package:dhara/features/player/widgets/glass.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

/// The player's info panel (key `I`): where the video comes from and how
/// playing it goes, one line each. Nothing in it can be clicked.
class PlaybackInfoPanel extends StatelessWidget {
  const PlaybackInfoPanel({super.key, required this.info});

  final PlaybackInfo info;

  @override
  Widget build(BuildContext context) {
    final rows = info.rows;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PanelHeading('Playback info'),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Text('Nothing is known yet.', style: _labelStyle)
            else
              for (final (index, (label, value)) in rows.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 138,
                        child: Text(label, maxLines: 1, style: _labelStyle),
                      ),
                      Expanded(
                        // Plain Text: some of these come from the file or
                        // the server.
                        child: Text(
                          value,
                          key: Key('info-value-$index'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _valueStyle,
                        ),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 6),
            const Text('I closes this.', style: _hintStyle),
          ],
        ),
      ),
    );
  }
}

const _labelStyle = TextStyle(
  fontFamily: DharaFonts.ui,
  fontSize: 13,
  height: 1.35,
  color: DharaColors.text2,
);

const _valueStyle = TextStyle(
  fontFamily: DharaFonts.ui,
  fontSize: 13,
  height: 1.35,
  fontWeight: FontWeight.w600,
  fontFeatures: [FontFeature.tabularFigures()],
  color: DharaColors.text,
);

const _hintStyle = TextStyle(
  fontFamily: DharaFonts.ui,
  fontSize: 12,
  color: DharaColors.text3,
);
