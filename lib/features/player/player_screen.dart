import 'dart:async';

import 'package:dhara/features/player/secure_player.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Plays a single, already validated `http`/`https` URL.
///
/// Uses media_kit's stock desktop controls for now; the custom controls from
/// the approved prototype replace them in a later increment.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.url});

  /// Must come from `parseMediaUrl`, never from raw input.
  final Uri url;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player = createPlayer();
  late final VideoController _video = VideoController(_player);
  StreamSubscription<String>? _errorSub;
  String? _error;

  @override
  void initState() {
    super.initState();
    _errorSub = _player.stream.error.listen((message) {
      if (mounted) setState(() => _error = message);
    });
    unawaited(_player.open(Media(widget.url.toString())));
  }

  @override
  void dispose() {
    unawaited(_errorSub?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Video(controller: _video),
          Positioned(
            top: 12,
            left: 12,
            child: IconButton.filledTonal(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          if (error != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 96,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xE6240A12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    // Plain Text widget: server-influenced strings are never
                    // interpreted as markup.
                    child: Text(
                      'Playback error: $error',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
