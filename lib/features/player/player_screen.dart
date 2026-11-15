import 'dart:async';

import 'package:dhara/core/net/media_url.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/core/window/fullscreen.dart';
import 'package:dhara/features/playback/copy_probe.dart';
import 'package:dhara/features/playback/smart_start.dart';
import 'package:dhara/features/player/player_tuning.dart';
import 'package:dhara/features/player/resume_store.dart';
import 'package:dhara/features/player/secure_player.dart';
import 'package:dhara/features/player/track_options.dart';
import 'package:dhara/features/player/widgets/player_controls.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Plays a queue of videos, one after the other, with the app's own
/// controls drawn over the video.
///
/// A video that has several copies is played from the one whose server
/// answers fastest right now, at the preferred quality (see `chooseCopy`).
/// Each video resumes where it was left, and when one ends the next starts
/// after a countdown the user can cancel.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.entries, this.initialIndex = 0})
    : assert(entries.length > 0),
      assert(initialIndex >= 0 && initialIndex < entries.length);

  /// The videos at [urls], each at that one address. They must come from
  /// `parseMediaUrl`, never from raw input.
  PlayerScreen.urls(List<Uri> urls, {Key? key})
    : this(key: key, entries: [for (final url in urls) PlayEntry.url(url)]);

  final List<PlayEntry> entries;
  final int initialIndex;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  /// How often the position is written while playing.
  static const _saveInterval = Duration(seconds: 5);

  /// How long to wait for a file to open before giving up on resuming.
  static const _loadTimeout = Duration(seconds: 15);

  /// How long an error stays up once the video is playing.
  static const _errorDuration = Duration(seconds: 8);

  /// How long the "Resumed from ..." pill stays up.
  static const _resumeNoticeDuration = Duration(seconds: 7);

  /// How long a server has to answer when it is asked for a video.
  static const _askTimeout = Duration(seconds: 2);

  /// How this player reads ahead and decodes: the settings as they were
  /// when it was opened.
  late final PlayerTuning _tuning = PlayerTuning.of(
    SettingsScope.read(context),
  );

  late final Player _player = createPlayer();
  late final VideoController _video = createVideoController(_player, _tuning);
  late final ResumeStore _resume = ResumeStoreScope.of(context);
  late final SourceStore _sources;

  /// What is asking the servers for the current video, while it does.
  CopyProber? _asking;
  final _subscriptions = <StreamSubscription<Object?>>[];
  late final Future<void> _started;

  late int _index = widget.initialIndex;
  String? _error;
  Timer? _errorTimer;
  bool _fullscreen = false;

  // Resume and "up next" state of the current video.
  Duration? _resumedFrom;
  Timer? _resumeNoticeTimer;
  bool _autoNextCancelled = false;

  // Which copy of the current video is played (until that is decided,
  // the first of them), and how many are being asked for.
  late Uri _url = _entry.candidates.first.url;
  int _choosingFrom = 0;

  // A position that was taken over from another copy of the video: where
  // that copy was left is forgotten once this one has a position of its
  // own, so that the video is not kept as unfinished twice.
  Uri? _carriedFrom;

  // For the info panel: where the current video is fetched from, how
  // long that server took to answer, how many copies were asked for, and
  // how long the video took to start.
  Uri? _playingFrom;
  Duration? _serverAnswered;
  CopyChoice? _choice;
  Duration? _startedIn;
  final _sinceOpen = Stopwatch();
  Duration _startPosition = Duration.zero;
  List<String> _optionsNotTaken = const [];

  // Positions are only saved once the current video has reported its
  // duration; until then the player may still hold the previous one's.
  bool _progressReady = false;
  Duration _lastSavedPosition = Duration.zero;

  PlayEntry get _entry => widget.entries[_index];

  String _titleAt(int index) {
    final entry = widget.entries[index];
    return entry.title ?? mediaTitleFromUrl(entry.candidates.first.url);
  }

  /// A video may come from the hosts in this queue and from the
  /// configured sources (looked up each time: the list can change).
  bool _mayPlayFrom(String host) =>
      widget.entries.any(
        (entry) => entry.candidates.any((copy) => copy.url.host == host),
      ) ||
      _sources.sources.any(
        (source) => source.baseUrls.any((url) => url.host == host),
      );

  bool get _hasNext => _index + 1 < widget.entries.length;

  @override
  void initState() {
    super.initState();
    // Looked up now: the redirect check may still be running when this
    // screen is gone, and must not touch the widget tree then.
    _sources = SourcesScope.read(context).store;
    final stream = _player.stream;
    _subscriptions.addAll([
      stream.error.listen(_showError),
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

  /// Shows what libmpv reported. While the video plays on, the message
  /// goes away by itself; it stays if nothing is playing, since it is then
  /// the only explanation there is.
  void _showError(String message) {
    // A sound track without a decoder: the controls switch to another
    // track and say so themselves.
    if (!mounted || undecodableAudioCodec(message) != null) return;
    setState(() => _error = message);
    _errorTimer?.cancel();
    _errorTimer = Timer.periodic(_errorDuration, (timer) {
      if (!mounted || !_progressReady) return;
      timer.cancel();
      setState(() => _error = null);
    });
  }

  /// Hardens the player first; a URL is only opened once every security
  /// option has been verified. Never throws.
  Future<void> _start() async {
    try {
      await hardenPlayer(_player);
      // Smoothness, not safety: the video plays whatever this reports.
      _optionsNotTaken = await tunePlayer(_player, _tuning);
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

  /// Opens the video at [_index], from the copy of it that is fastest
  /// right now, resuming from the saved position if any.
  Future<void> _openCurrent() async {
    final index = _index;
    final candidates = _entry.candidates;
    // Where it was left, on whichever copy that was.
    Uri? resumeUrl;
    Duration? resumeFrom;
    for (final copy in candidates) {
      final position = _resume.positionFor(copy.url);
      if (position != null) {
        resumeUrl = copy.url;
        resumeFrom = position;
        break;
      }
    }
    _url = resumeUrl ?? candidates.first.url;
    _carriedFrom = null;
    _progressReady = false;
    _lastSavedPosition = resumeFrom ?? Duration.zero;
    _resumeNoticeTimer?.cancel();
    _errorTimer?.cancel();
    _startPosition = resumeFrom ?? Duration.zero;
    _sinceOpen
      ..reset()
      ..start();
    setState(() {
      _error = null;
      _autoNextCancelled = false;
      _resumedFrom = resumeFrom;
      _playingFrom = null;
      _serverAnswered = null;
      _choice = null;
      _startedIn = null;
      _choosingFrom = candidates.length;
    });
    // The servers are asked for the copies: which answers fastest, and
    // where it sends the player (FFmpeg would follow a redirect to any
    // host; the app follows them first, under its own rules).
    _asking?.close();
    final asking = _asking = CopyProber(
      isAllowedHost: _mayPlayFrom,
      timeout: _askTimeout,
    );
    final CopyChoice choice;
    try {
      choice = await chooseCopy(
        asking,
        candidates,
        preferred: SettingsScope.read(context).preferredQuality,
        resume: resumeUrl,
      );
    } on PlaybackBlocked catch (blocked) {
      if (mounted && _index == index) {
        setState(() {
          _error = blocked.message;
          _choosingFrom = 0;
        });
      }
      return;
    } finally {
      asking.close();
    }
    // The user may have left or moved on while the servers were asked.
    if (!mounted || _index != index) return;
    if (resumeUrl != null && resumeUrl != choice.url) _carriedFrom = resumeUrl;
    setState(() {
      _url = choice.url;
      _playingFrom = choice.address;
      _serverAnswered = choice.answeredIn;
      _choice = choice;
      _choosingFrom = 0;
    });
    // Resume positions and titles stay tied to the copy that was chosen;
    // only the player is pointed at where it leads.
    final media = Media(choice.address.toString());
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

  /// "DhakaFlix 7 (172.16.50.7)": the source a video is fetched from and
  /// its address, or the address alone. Plain text only.
  String _serverLabel(Uri url) {
    for (final source in _sources.sources) {
      if (source.baseUrls.any((base) => base.host == url.host)) {
        return '${source.name} (${url.host})';
      }
    }
    return url.host;
  }

  void _onPosition(Duration position) {
    // The picture moves: the video has started.
    if (_startedIn == null &&
        _progressReady &&
        _sinceOpen.isRunning &&
        _player.state.playing &&
        position > _startPosition) {
      _sinceOpen.stop();
      if (mounted) setState(() => _startedIn = _sinceOpen.elapsed);
    }
    if ((position - _lastSavedPosition).abs() >= _saveInterval) {
      _saveProgress();
    }
  }

  void _saveProgress() {
    if (!_progressReady) return;
    final state = _player.state;
    _lastSavedPosition = state.position;
    _resume.save(_url, position: state.position, duration: state.duration);
    _forgetCarried();
  }

  /// The video goes on from another copy now: where the earlier copy was
  /// left is forgotten once this one has a position of its own, or was
  /// watched to the end ([finished]). Until then the earlier one's is the
  /// only position there is.
  void _forgetCarried({bool finished = false}) {
    final from = _carriedFrom;
    if (from == null) return;
    if (!finished && _resume.positionFor(_url) == null) return;
    _resume.clear(from);
    _carriedFrom = null;
  }

  void _onCompleted() {
    if (!_progressReady) return;
    // Watched to the end: next time it starts from the beginning.
    _resume.finish(_url, duration: _player.state.duration);
    _forgetCarried(finished: true);
    if (_autoNext) _playNext();
  }

  /// The next video starts by itself: the setting allows it and this one's
  /// countdown was not cancelled.
  bool get _autoNext =>
      !_autoNextCancelled && SettingsScope.read(context).autoplayNext;

  void _playNext() {
    if (!_hasNext || !mounted) return;
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
    _errorTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _asking?.close();
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
    final choice = _choice;
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
            nextTitle: _hasNext ? _titleAt(_index + 1) : null,
            autoNext: _autoNext,
            onPlayNext: _playNext,
            onCancelAutoNext: () => setState(() => _autoNextCancelled = true),
            resumedFrom: _resumedFrom,
            onStartOver: _startOver,
            server: switch (_playingFrom) {
              null => null,
              final url => _serverLabel(url),
            },
            serverAnswered: _serverAnswered,
            copiesAsked: choice?.asked ?? 0,
            copiesAnswered: choice?.answered ?? 0,
            startedIn: _startedIn,
            optionsNotTaken: _optionsNotTaken,
          ),
          // While the servers are asked which has the video fastest.
          if (_choosingFrom > 1 && error == null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 120,
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    'Asking $_choosingFrom servers for the fastest copy …',
                    key: const Key('choosing-copy'),
                    style: const TextStyle(
                      fontFamily: DharaFonts.ui,
                      fontSize: 14,
                      color: DharaColors.text2,
                    ),
                  ),
                ),
              ),
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
