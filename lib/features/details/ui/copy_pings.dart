import 'dart:async';

import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/playback/copy_choice.dart';
import 'package:dhara/features/playback/copy_probe.dart';
import 'package:dhara/features/playback/media_sessions.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:flutter/widgets.dart';

/// What [CopyPings] tells the list of copies it is around.
@immutable
class LivePings {
  const LivePings({
    required this.byFile,
    required this.pinging,
    required this.ping,
  });

  /// The answers so far, by the copy's file id. Empty until asked.
  final Map<int, CopyProbe> byFile;

  /// Servers are being asked right now.
  final bool pinging;

  /// Asks again; `null` where the app has nothing to ask with.
  final VoidCallback? ping;

  /// The copies were asked, and every answer is in.
  bool get done => !pinging && byFile.isNotEmpty;
}

/// Asks the servers for the [copies] of one film or episode when it comes
/// on screen, and again when told to, and hands the answers to [builder]
/// as they arrive.
///
/// Only copies that can be played are asked, and only when there are at
/// most [autoLimit] of them (one small request each). Without a
/// [CopyProbeScope] that makes probers (in tests) nothing is asked.
class CopyPings extends StatefulWidget {
  const CopyPings({
    super.key,
    required this.copies,
    required this.sources,
    required this.builder,
  });

  static const autoLimit = 12;

  final List<TitleCopy> copies;
  final SourceStore sources;
  final Widget Function(BuildContext context, LivePings pings) builder;

  @override
  State<CopyPings> createState() => _CopyPingsState();
}

class _CopyPingsState extends State<CopyPings> {
  CopyProber? _prober;
  MediaSessions? _sessions;
  StreamSubscription<CopyProbe>? _answers;

  // Counts the pings: an earlier one that is still signing in is dropped.
  int _pings = 0;
  var _byFile = const <int, CopyProbe>{};
  var _pinging = false;
  var _started = false;

  List<TitleCopy> get _askable => [
    for (final copy in widget.copies)
      if (canPlayCopy(copy, widget.sources)) copy,
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _prober = CopyProbeScope.newProber(context);
    _sessions = MediaSessionsScope.read(context);
    final count = _askable.length;
    if (_prober != null && count > 0 && count <= CopyPings.autoLimit) {
      unawaited(_ping());
    }
  }

  @override
  void dispose() {
    unawaited(_answers?.cancel());
    _prober?.close();
    super.dispose();
  }

  Future<void> _ping() async {
    final prober = _prober;
    final copies = _askable;
    if (prober == null || copies.isEmpty) return;
    final ping = ++_pings;
    unawaited(_answers?.cancel());
    setState(() {
      _byFile = const {};
      _pinging = true;
    });
    // Files of a media server are asked for with its session.
    final urls = [for (final copy in copies) copy.url];
    final headers =
        await _sessions?.headersForAll(urls) ??
        const <Uri, Map<String, String>>{};
    if (!mounted || ping != _pings) return;
    _answers = prober
        .probe(urls, headers: headers)
        .listen(
          (probe) {
            // A session the server no longer takes: signed in afresh the
            // next time.
            if (probe.refused) _sessions?.forget(probe.url);
            if (!mounted) return;
            setState(() {
              _byFile = {
                ..._byFile,
                for (final copy in copies)
                  if (copy.url == probe.url) copy.fileId: probe,
              };
            });
          },
          onDone: () {
            if (mounted) setState(() => _pinging = false);
          },
        );
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    LivePings(
      byFile: _byFile,
      pinging: _pinging,
      ping: _prober == null || _askable.isEmpty
          ? null
          : () => unawaited(_ping()),
    ),
  );
}
