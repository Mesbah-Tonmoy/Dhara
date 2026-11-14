import 'dart:async';

import 'package:dhara/core/net/media_url.dart';
import 'package:dhara/features/indexer/ui/index_screen.dart';
import 'package:dhara/features/metadata/ui/titles_screen.dart';
import 'package:dhara/features/player/player_screen.dart';
import 'package:dhara/features/sources/ui/server_discovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Temporary Phase 2 entry point: paste one or more video URLs and play them
/// in order. Replaced by the real Home screen in Phase 6.
class OpenUrlScreen extends StatefulWidget {
  const OpenUrlScreen({super.key});

  @override
  State<OpenUrlScreen> createState() => _OpenUrlScreenState();
}

class _OpenUrlScreenState extends State<OpenUrlScreen> {
  final _urlController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _play() {
    final parsed = parseMediaUrls(_urlController.text);
    if (!parsed.isValid) {
      final line = parsed.invalidLine;
      setState(() {
        _error = line == null || !_urlController.text.trim().contains('\n')
            ? 'Enter a full http:// or https:// video URL.'
            : 'Line $line is not a full http:// or https:// video URL.';
      });
      return;
    }
    setState(() => _error = null);
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(urls: parsed.urls),
        ),
      ),
    );
  }

  /// Enter plays; Shift+Enter starts a new line for another URL.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter || HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) _play();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Dhara',
                  key: const Key('app-title'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Paste a video URL to play it',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                Focus(
                  onKeyEvent: _onKey,
                  child: TextField(
                    key: const Key('url-field'),
                    controller: _urlController,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.multiline,
                    minLines: 1,
                    maxLines: 6,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'http://server/path/video.mkv',
                      helperText: 'Several URLs, one per line (Shift+Enter), '
                          'play one after the other.',
                      errorText: _error,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('play-button'),
                  onPressed: _play,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Play'),
                  ),
                ),
                const SizedBox(height: 28),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      key: const Key('open-discovery'),
                      onPressed: () => unawaited(
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const ServerDiscoveryScreen(),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.dns_outlined),
                      label: const Text('Server Discovery (BDIX Tester)'),
                    ),
                    TextButton.icon(
                      key: const Key('open-index'),
                      onPressed: () => unawaited(
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const IndexScreen(),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.video_library_outlined),
                      label: const Text('Library index and search'),
                    ),
                    TextButton.icon(
                      key: const Key('open-titles'),
                      onPressed: () => unawaited(
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const TitlesScreen(),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.movie_outlined),
                      label: const Text('Films and shows'),
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
