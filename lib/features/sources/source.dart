import 'package:flutter/foundation.dart';

/// How a source exposes its files. Each type is read by one adapter.
enum SourceType {
  directoryListing('directory_listing'),
  h5ai('h5ai'),
  emby('emby'),
  jellyfin('jellyfin'),
  customSite('custom_site');

  const SourceType(this.jsonName);

  /// The value used in source-list JSON.
  final String jsonName;
}

/// What a source mostly holds. The JSON value is the enum name.
enum SourceCategory { movies, series, anime, mixed }

/// One BDIX media server: where it is and how to read it.
///
/// This is only the shareable description (the shape documented in
/// `assets/sources/README.md`). Whether a source is enabled on this PC is
/// kept apart, in `SourceStore`.
///
/// Every text field can come from an imported list, so show it only through
/// a plain `Text` widget.
@immutable
class Source {
  const Source({
    required this.id,
    required this.name,
    this.provider,
    this.isp,
    required this.type,
    required this.category,
    required this.baseUrls,
    this.portalUrl,
    this.notes,
  });

  /// Unique within a list: lower-case letters, digits and "-".
  final String id;
  final String name;

  /// Groups the servers of one operator.
  final String? provider;

  /// The ISP that runs the server, if known.
  final String? isp;
  final SourceType type;
  final SourceCategory category;

  /// Folder URLs (ending in "/") to read; each is crawled as its own root.
  final List<Uri> baseUrls;

  /// The operator's landing page.
  final Uri? portalUrl;
  final String? notes;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'provider': provider,
        'isp': isp,
        'type': type.jsonName,
        'category': category.name,
        'baseUrls': [for (final url in baseUrls) url.toString()],
        'portalUrl': portalUrl?.toString(),
        'notes': notes,
      };

  @override
  bool operator ==(Object other) =>
      other is Source &&
      other.id == id &&
      other.name == name &&
      other.provider == provider &&
      other.isp == isp &&
      other.type == type &&
      other.category == category &&
      listEquals(other.baseUrls, baseUrls) &&
      other.portalUrl == portalUrl &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        provider,
        isp,
        type,
        category,
        Object.hashAll(baseUrls),
        portalUrl,
        notes,
      );
}
