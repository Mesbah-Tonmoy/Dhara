import 'dart:async';

import 'package:dhara/core/net/media_url.dart';
import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/core/window/fullscreen.dart';
import 'package:dhara/features/player/playback_url.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:dhara/features/player/secure_player.dart';
import 'package:dhara/features/player/widgets/player_controls.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Plays a queue of already validated `http`/`https` URLs, one after the
/// other, with the app's own controls drawn over the video.
///
/// Each video resumes where it was left, and when one ends the next starts
/// after a countdown the user can cancel.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.urls,
    this.initialIndex = 0,
    this.titles,
  })  : assert(urls.length > 0),
        assert(initialIndex >= 0 && initialIndex < urls.length),
        assert(titles == null || titles.length == urls.length);

  /// Must come from `parseMediaUrl`, never from raw input.
  final List<Uri> urls;
  final int initialIndex;

  /// What to call each video ("The Bay · S1 · E2"), in the order of [urls];
  /// without it, each goes by its file name. Shown as plain text only.
  final List<String>? titles;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  /// How often the position is written while playing.
  static const _saveInterval = Duration(seconds: 5);

  /// How long to wait for a file to open before giving up on resuming.
  static const _loadTimeout = Duration(seconds: 15);

  /// How long the "Resumed from ..." pill stays up.
  static const _resumeNoticeDuration = Duration(seconds: 7);

  late final Player _player = createPlayer();
  late final VideoController _video = VideoController(_player);
  late final ResumeStore _resume = ResumeStoreScope.of(context);
  late final SourceStore _sources;

  /// Checks where a video's server redirects to before the player opens
  /// it (see [resolvePlaybackUrl]).
  late final SafeHttpClient _http = SafeHttpClient(
    isAllowedHost: _mayPlayFrom,
    timeout: const Duration(seconds: 5),
  );
  final _subscriptions = <StreamSubscription<Object?>>[];
  late final Future<void> _started;

  late int _index = widget.initialIndex;
  String? _error;
  bool _fullscreen = false;

  // Resume and "up next" state of the current video.
  Duration? _resumedFrom;
  Timer? _resumeNoticeTimer;
  bool _autoNextCancelled = false;

  // Positions are only saved once the current video has reported its
  // duration; until then the player may still hold the previous one's.
  bool _progressReady = false;
  Duration _lastSavedPosition = Duration.zero;

  Uri get _url => widget.urls[_index];

  String _titleAt(int index) =>
      widget.titles?[index] ?? mediaTitleFromUrl(widget.urls[index]);

  /// A video may come from the hosts in this queue and from the
  /// configured sources (looked up each time: the list can change).
  bool _mayPlayFrom(String host) =>
      widget.urls.any((url) => url.host == host) ||
      _sources.sources.any(
        (source) => source.baseUrls.any((url) => url.host == host),
      );

  Uri? get _nextUrl =>
      _index + 1 < widget.urls.length ? widget.urls[_index + 1] : null;

  @override
  void initState() {
    super.initState();
    // Looked up now: the redirect check may still be running when this
    // screen is gone, and must not touch the widget tree then.
    _sources = SourcesScope.read(context).store;
    final stream = _player.stream;
    _subscriptions.addAll([
      stream.error.listen((message) {
        if (mounted) setState(() => _error = message);
      }),
      stream.duration.listen((duration) {
        if (duration > Duration.zero) _progressReady = true;
      }),
      stream.position.listen(_onPosition),
      stream.playing.listen((playing) {
        if (!playing) _saveProgress();
      }),
      stream.completed.listen((completed) {
        if (completed) _onCompleted();
      }),
    ]);
    _started = _start();
  }

  /// Hardens the player first; a URL is only opened once every security
  /// option has been verified. Never throws.
  Future<void> _start() async {
    try {
      await hardenPlayer(_player);
      if (!mounted) return;
      await _openCurrent();
    } on PlayerHardeningError {
      if (mounted) {
        setState(() {
          _error = 'Player security check failed, so playback was blocked.';
        });
      }
    }
  }

  /// Opens the video at [_index], resuming from the saved position if any.
  Future<void> _openCurrent() async {
    final index = _index;
    final resumeFrom = _resume.positionFor(_url);
    _progressReady = false;
    _lastSavedPosition = resumeFrom ?? Duration.zero;
    _resumeNoticeTimer?.cancel();
    setState(() {
      _error = null;
      _autoNextCancelled = false;
      _resumedFrom = resumeFrom;
    });
    final Uri address;
    try {
      address = await resolvePlaybackUrl(_http, _url);
    } on PlaybackBlocked catch (blocked) {
      if (mounted && _index == index) {
        setState(() => _error = blocked.message);
      }
      return;
    }
    // The user may have left or moved on while the server was asked.
    if (!mounted || _index != index) return;
    // Resume positions and titles stay tied to the URL that was asked for;
    // only the player is pointed at where it leads.
    final media = Media(address.toString());
    if (resumeFrom == null) {
      await _player.open(media);
      return;
    }

    _resumeNoticeTimer = Timer(_resumeNoticeDuration, () {
      if (mounted) setState(() => _resumedFrom = null);
    });
    // Load paused, jump to the saved position once the file is open, then
    // play. (Seeking a loaded file is the path every manual seek takes.)
    final loaded = _player.stream.duration
        .firstWhere((duration) => duration > Duration.zero)
        .timeout(_loadTimeout, onTimeout: () => Duration.zero);
    await _player.open(media, play: false);
    await loaded;
    // The user may have left or moved on while the file was loading.
    if (!mounted || _index != index) return;
    await _player.seek(resumeFrom);
    await _player.play();
  }

  void _onPosition(Duration position) {
    if ((position - _lastSavedPosition).abs() >= _saveInterval) {
      _saveProgress();
    }
  }

  void _saveProgress() {
    if (!_progressReady) return;
    final state = _player.state;
    _lastSavedPosition = state.position;
    _resume.save(_url, position: state.position, duration: state.duration);
  }

  void _onCompleted() {
    if (!_progressReady) return;
    // Watched to the end: next time it starts from the beginning.
    _resume.finish(_url, duration: _player.state.duration);
    if (_autoNext) _playNext();
  }

  /// The next video starts by itself: the setting allows it and this one's
  /// countdown was not cancelled.
  bool get _autoNext =>
      !_autoNextCancelled && SettingsScope.read(context).autoplayNext;

  void _playNext() {
    if (_nextUrl == null || !mounted) return;
    _saveProgress();
    _index++;
    unawaited(_openCurrent());
  }

  void _startOver() {
    _resumeNoticeTimer?.cancel();
    setState(() => _resumedFrom = null);
    unawaited(_player.seek(Duration.zero));
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    unawaited(setWindowFullscreen(_fullscreen));
  }

  @override
  void dispose() {
    _saveProgress();
    _resumeNoticeTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _http.close();
    // Fullscreen belongs to the player; the rest of the app is windowed.
    if (_fullscreen) unawaited(setWindowFullscreen(false));
    // Dispose only after start-up has settled, so libmpv is never torn down
    // while options are still being applied.
    unawaited(_started.whenComplete(_player.dispose));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final nextUrl = _nextUrl;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // `controls: null` turns media_kit's stock controls off; ours sit
          // on top.
          Video(
            controller: _video,
            controls: null,
            // Subtitles are drawn by libmpv (see createPlayer); the Flutter
            // text overlay would show them a second time.
            subtitleViewConfiguration: const SubtitleViewConfiguration(
              visible: false,
            ),
          ),
          PlayerControls(
            player: _player,
            settings: SettingsScope.read(context),
            mediaUrl: _url,
            title: _titleAt(_index),
            onBack: () => Navigator.of(context).maybePop(),
            fullscreen: _fullscreen,
            onToggleFullscreen: _toggleFullscreen,
            nextTitle: nextUrl == null ? null : _titleAt(_index + 1),
            autoNext: _autoNext,
            onPlayNext: _playNext,
            onCancelAutoNext: () => setState(() => _autoNextCancelled = true),
            resumedFrom: _resumedFrom,
            onStartOver: _startOver,
          ),
          if (error != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 120,
              child: IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xE6240A12),
                      borderRadius: BorderRadius.circular(DharaRadii.md),
                      border: Border.all(color: DharaColors.bad),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      // Plain Text widget: server-influenced strings are
                      // never interpreted as markup.
                      child: Text(
                        'Playback error: $error',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
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
