import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_list.dart';
import 'package:flutter/services.dart';

/// The servers checked by hand: each with its type, what it holds and notes.
const starterSourcesAsset = 'assets/sources/starter_sources.json';

/// Servers taken from a public list as they stood there: nobody has looked
/// at them, so their type is only known once the BDIX Tester has asked them.
const candidateSourcesAsset = 'assets/sources/candidate_sources.json';

/// Loads the sources shipped with the app: the starter list, then the
/// candidates. None of them is enabled by being listed.
///
/// Throws a [SourceFormatException] if a bundled file is broken; the tests
/// in `test/assets` keep that from shipping.
Future<List<Source>> loadStarterSources(AssetBundle bundle) async {
  // Read once at start-up, so there is no point keeping the text cached.
  final starter = parseSourceList(
    await bundle.loadString(starterSourcesAsset, cache: false),
  );
  final candidates = parseSourceList(
    await bundle.loadString(candidateSourcesAsset, cache: false),
  );
  return mergeStarterSources(starter, candidates);
}

/// [starter] followed by those of [candidates] it does not already have:
/// a candidate with the id of a starter source, or with a server address
/// (host and port) one of them reads, is left out.
List<Source> mergeStarterSources(
  List<Source> starter,
  List<Source> candidates,
) {
  final ids = {for (final source in starter) source.id};
  final servers = {
    for (final source in starter)
      for (final url in source.baseUrls) url.authority,
  };
  return [
    ...starter,
    for (final source in candidates)
      if (!ids.contains(source.id) &&
          !source.baseUrls.any((url) => servers.contains(url.authority)))
        source,
  ];
}
