import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_list.dart';
import 'package:flutter/services.dart';

const starterSourcesAsset = 'assets/sources/starter_sources.json';

/// Loads the source list shipped with the app.
///
/// Throws a [SourceFormatException] if the bundled file is broken; the
/// tests in `test/assets` keep that from shipping.
Future<List<Source>> loadStarterSources(AssetBundle bundle) async {
  // Read once at start-up, so there is no point keeping the text cached.
  final text = await bundle.loadString(starterSourcesAsset, cache: false);
  return parseSourceList(text);
}
