import 'package:dhara/core/net/media_url.dart';
import 'package:dhara/features/metadata/metadata_store.dart';
import 'package:dhara/features/playback/copy_probe.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_store.dart';

/// Which copy of a film or an episode to play when the user has not picked
/// one, and in which order to list the copies.
///
/// The rule: a copy on a server that answers, then the sharpest picture,
/// then the server that answers fastest, then the larger file. "Answers"
/// is what a live ping of the copy found just now (see `CopyProber`),
/// where there is one, and else what the server's last test found.

/// How a copy's server stood at its last test.
enum CopyReach {
  /// The server did not answer.
  offline,

  /// The server was never tested from this connection.
  unknown,

  /// The server answered.
  online,
}

/// [pings] are the live answers, by file id (none: the last test counts).
CopyReach reachOf(
  TitleCopy copy,
  SourceStore sources, [
  Map<int, CopyProbe> pings = const {},
]) {
  if (pings[copy.fileId] case final live?) {
    return live.ok ? CopyReach.online : CopyReach.offline;
  }
  return switch (sources.healthOf(copy.sourceId)) {
    null => CopyReach.unknown,
    final health => health.reachable ? CopyReach.online : CopyReach.offline,
  };
}

/// How long the copy's server took to answer: just now if it was asked
/// ([pings]), else at its last test. `null` if it did not answer.
Duration? pingOf(
  TitleCopy copy,
  SourceStore sources, [
  Map<int, CopyProbe> pings = const {},
]) {
  if (pings[copy.fileId] case final live?) return live.ok ? live.time : null;
  final health = sources.healthOf(copy.sourceId);
  return health != null && health.reachable ? health.ping : null;
}

Source? sourceOf(TitleCopy copy, SourceStore sources) {
  for (final source in sources.sources) {
    if (source.id == copy.sourceId) return source;
  }
  return null;
}

/// Whether the player can be given this copy: a plain `http`/`https`
/// address without credentials, on a server that needs no sign-in.
bool canPlayCopy(TitleCopy copy, SourceStore sources) {
  final url = copy.url;
  final type = sourceOf(copy, sources)?.type;
  return allowedUrlSchemes.contains(url.scheme) &&
      url.host.isNotEmpty &&
      url.userInfo.isEmpty &&
      type != SourceType.emby &&
      type != SourceType.jellyfin;
}

/// [copies] in the order to offer them: the best first (see above), what
/// cannot be played last.
List<TitleCopy> rankCopies(
  Iterable<TitleCopy> copies,
  SourceStore sources, {
  Map<int, CopyProbe> pings = const {},
}) {
  int compare(TitleCopy a, TitleCopy b) {
    final playable =
        (canPlayCopy(b, sources) ? 1 : 0) - (canPlayCopy(a, sources) ? 1 : 0);
    if (playable != 0) return playable;
    final reach =
        reachOf(b, sources, pings).index - reachOf(a, sources, pings).index;
    if (reach != 0) return reach;
    final height = (b.height ?? 0) - (a.height ?? 0);
    if (height != 0) return height;
    const never = Duration(days: 1);
    final ping = (pingOf(a, sources, pings) ?? never).compareTo(
      pingOf(b, sources, pings) ?? never,
    );
    if (ping != 0) return ping;
    final size = (b.size ?? 0).compareTo(a.size ?? 0);
    return size != 0 ? size : a.fileId.compareTo(b.fileId);
  }

  return copies.toList()..sort(compare);
}

/// The copy to play of [copies] (all of one film, or of one episode);
/// `null` if none can be played. Trailers and samples do not count.
TitleCopy? bestCopy(Iterable<TitleCopy> copies, SourceStore sources) {
  final ranked = rankCopies([
    for (final copy in copies)
      if (copy.extra == null && canPlayCopy(copy, sources)) copy,
  ], sources);
  return ranked.isEmpty ? null : ranked.first;
}

/// The episode a copy is of: season (or `null` for a show numbered
/// straight through) and number.
typedef EpisodeKey = (int? season, int episode);

EpisodeKey? episodeOf(TitleCopy copy) => switch (copy.episode) {
  null => null,
  final episode => (copy.season, episode),
};

/// The episodes [copies] hold, in order, each with its copies. Trailers,
/// samples and videos that are no episode are left out. The specials
/// (season 0) come after the seasons: a show starts with season 1.
Map<EpisodeKey, List<TitleCopy>> episodesIn(Iterable<TitleCopy> copies) {
  final episodes = <EpisodeKey, List<TitleCopy>>{};
  for (final copy in copies) {
    final key = episodeOf(copy);
    if (key == null || copy.extra != null) continue;
    (episodes[key] ??= []).add(copy);
  }
  // Seasons first, then the specials, then what is numbered straight
  // through.
  int place(int? season) => switch (season) {
    null => 1 << 30,
    0 => (1 << 30) - 1,
    _ => season,
  };
  final keys = episodes.keys.toList()
    ..sort((a, b) {
      final season = place(a.$1).compareTo(place(b.$1));
      return season != 0 ? season : a.$2.compareTo(b.$2);
    });
  return {for (final key in keys) key: episodes[key]!};
}

/// What to play when [start] is chosen: [start] itself, then one copy of
/// each episode after it. For those, a copy on the same server as [start]
/// is taken if it can be played, otherwise the best one.
List<TitleCopy> queueFrom(
  TitleCopy start,
  Iterable<TitleCopy> copies,
  SourceStore sources, {
  int limit = 50,
}) {
  final own = episodeOf(start);
  if (own == null || start.extra != null) return [start];
  final queue = [start];
  var reached = false;
  for (final MapEntry(:key, :value) in episodesIn(copies).entries) {
    if (key == own) {
      reached = true;
      continue;
    }
    if (!reached) continue;
    if (queue.length >= limit) break;
    final next =
        bestCopy([
          for (final copy in value)
            if (copy.sourceId == start.sourceId) copy,
        ], sources) ??
        bestCopy(value, sources);
    if (next != null) queue.add(next);
  }
  return queue;
}
