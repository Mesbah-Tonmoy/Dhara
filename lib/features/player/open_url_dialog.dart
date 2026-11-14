import 'dart:async';

import 'package:dhara/core/net/media_url.dart';
import 'package:dhara/features/player/player_screen.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void _openPlayer(BuildContext context, List<Uri> urls) => unawaited(
  Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute<void>(builder: (_) => PlayerScreen(urls: urls))),
);

/// Asks for one or more video addresses and plays them in order: the way
/// to play something that is not in the library.
///
/// Only full `http://` and `https://` addresses are accepted; anything
/// else is refused before a player exists.
Future<void> showOpenUrlDialog(
  BuildContext context, {
  void Function(BuildContext context, List<Uri> urls) onPlay = _openPlayer,
}) async {
  final urls = await showDialog<List<Uri>>(
    context: context,
    builder: (_) => const _OpenUrlDialog(),
  );
  if (urls != null && context.mounted) onPlay(context, urls);
}

class _OpenUrlDialog extends StatefulWidget {
  const _OpenUrlDialog();

  @override
  State<_OpenUrlDialog> createState() => _OpenUrlDialogState();
}

class _OpenUrlDialogState extends State<_OpenUrlDialog> {
  final _urls = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _urls.dispose();
    super.dispose();
  }

  void _play() {
    final parsed = parseMediaUrls(_urls.text);
    if (!parsed.isValid) {
      final line = parsed.invalidLine;
      setState(() {
        _error = line == null || !_urls.text.trim().contains('\n')
            ? 'Enter a full http:// or https:// video URL.'
            : 'Line $line is not a full http:// or https:// video URL.';
      });
      return;
    }
    Navigator.of(context).pop(parsed.urls);
  }

  /// Enter plays; Shift+Enter starts a new line for another URL.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter || HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) _play();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: DharaColors.bgElev,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DharaRadii.lg),
        side: const BorderSide(color: DharaColors.stroke),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 38 * rem),
        child: Padding(
          padding: const EdgeInsets.all(DharaSpace.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Play a URL',
                style: TextStyle(
                  fontFamily: DharaFonts.display,
                  fontSize: DharaType.xl,
                  fontWeight: DharaType.bold,
                  color: DharaColors.text,
                ),
              ),
              const SizedBox(height: DharaSpace.s1),
              const Text(
                'For a video that is not in the library. Several URLs, one '
                'per line (Shift+Enter), play one after the other.',
                style: TextStyle(
                  fontSize: DharaType.sm,
                  height: DharaType.body,
                  color: DharaColors.text2,
                ),
              ),
              const SizedBox(height: DharaSpace.s4),
              Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  key: const Key('url-field'),
                  controller: _urls,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.multiline,
                  minLines: 1,
                  maxLines: 6,
                  style: const TextStyle(fontSize: DharaType.md),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'http://server/path/video.mkv',
                    errorText: _error,
                  ),
                ),
              ),
              const SizedBox(height: DharaSpace.s5),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  DharaButton(
                    label: 'Cancel',
                    small: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: DharaSpace.s2),
                  DharaButton(
                    key: const Key('play-button'),
                    label: 'Play',
                    icon: DharaIcons.play,
                    style: DharaButtonStyle.primary,
                    small: true,
                    onPressed: _play,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
