import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/sources/adapters/directory_listing_adapter.dart';
import 'package:dhara/features/sources/adapters/emby_adapter.dart';
import 'package:dhara/features/sources/adapters/h5ai_adapter.dart';
import 'package:dhara/features/sources/adapters/source_adapter.dart';
import 'package:dhara/features/sources/source.dart';

/// The adapter that reads the base URL [baseUrl] of a source of [type], or
/// `null` if no adapter exists for that type (a custom website).
///
/// An Emby/Jellyfin adapter signs in to one server and keeps that session,
/// so make one per base URL and keep using it. [deviceId] is what it tells
/// the server when signing in (see `loadOrCreateDeviceId`).
SourceAdapter? adapterFor(
  SourceType type,
  SafeHttpClient client, {
  required Uri baseUrl,
  required String deviceId,
}) => switch (type) {
  SourceType.directoryListing => DirectoryListingAdapter(client),
  SourceType.h5ai => H5aiAdapter(client),
  SourceType.emby || SourceType.jellyfin => EmbyAdapter(
    client,
    baseUrl: baseUrl,
    deviceId: deviceId,
  ),
  SourceType.customSite => null,
};
