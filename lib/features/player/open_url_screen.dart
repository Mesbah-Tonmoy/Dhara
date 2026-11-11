import 'dart:async';

import 'package:dhara/core/net/media_url.dart';
import 'package:dhara/features/player/player_screen.dart';
import 'package:flutter/material.dart';

/// Temporary Phase 2 entry point: paste a video URL and play it.
/// Replaced by the real Home screen in Phase 6.
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
    final url = parseMediaUrl(_urlController.text);
    if (url == null) {
      setState(() => _error = 'Enter a full http:// or https:// video URL.');
      return;
    }
    setState(() => _error = null);
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PlayerScreen(url: url)),
      ),
    );
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
                TextField(
                  key: const Key('url-field'),
                  controller: _urlController,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _play(),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: 'http://server/path/video.mkv',
                    errorText: _error,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
