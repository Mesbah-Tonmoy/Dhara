import 'dart:convert';

import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_list.dart';
import 'package:flutter/material.dart';

/// Names for the source types and categories, as shown in the app.
String sourceTypeLabel(SourceType type) => switch (type) {
      SourceType.directoryListing => 'Folder listing',
      SourceType.h5ai => 'h5ai',
      SourceType.emby => 'Emby',
      SourceType.jellyfin => 'Jellyfin',
      SourceType.customSite => 'Website',
    };

String sourceCategoryLabel(SourceCategory category) => switch (category) {
      SourceCategory.movies => 'Movies',
      SourceCategory.series => 'Series',
      SourceCategory.anime => 'Anime',
      SourceCategory.mixed => 'Mixed',
    };

/// An id for a new source called [name] that none of [taken] uses:
/// `"My Server!"` becomes `my-server`, then `my-server-2`, and so on.
String uniqueSourceId(String name, Set<String> taken) {
  var base = name
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (base.length > 48) {
    base = base.substring(0, 48).replaceAll(RegExp(r'-+$'), '');
  }
  if (base.isEmpty) base = 'source';

  var id = base;
  for (var n = 2; taken.contains(id); n++) {
    id = '$base-$n';
  }
  return id;
}

/// Asks for the details of a new source, or of [source] when editing.
/// Returns the checked source, or `null` if the user cancels.
Future<Source?> showSourceFormDialog(
  BuildContext context, {
  Source? source,
  required Set<String> takenIds,
}) =>
    showDialog<Source>(
      context: context,
      builder: (_) => _SourceFormDialog(source: source, takenIds: takenIds),
    );

class _SourceFormDialog extends StatefulWidget {
  const _SourceFormDialog({required this.source, required this.takenIds});

  final Source? source;
  final Set<String> takenIds;

  @override
  State<_SourceFormDialog> createState() => _SourceFormDialogState();
}

class _SourceFormDialogState extends State<_SourceFormDialog> {
  late final _name = TextEditingController(text: widget.source?.name);
  late final _urls = TextEditingController(
    text: widget.source?.baseUrls.join('\n'),
  );
  late final _provider = TextEditingController(text: widget.source?.provider);
  late final _isp = TextEditingController(text: widget.source?.isp);
  late final _portal = TextEditingController(
    text: widget.source?.portalUrl?.toString(),
  );
  late final _notes = TextEditingController(text: widget.source?.notes);
  late var _type = widget.source?.type ?? SourceType.directoryListing;
  late var _category = widget.source?.category ?? SourceCategory.mixed;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_name, _urls, _provider, _isp, _portal, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The same check every source list goes through decides what is valid,
  /// so whatever is accepted here can be saved, exported and read back.
  void _save() {
    final portal = _portal.text.trim();
    final json = <String, Object?>{
      'id': widget.source?.id ?? uniqueSourceId(_name.text, widget.takenIds),
      'name': _name.text,
      'provider': _provider.text,
      'isp': _isp.text,
      'type': _type.jsonName,
      'category': _category.name,
      'baseUrls': [
        for (final line in const LineSplitter().convert(_urls.text))
          if (line.trim().isNotEmpty) line.trim(),
      ],
      'portalUrl': portal.isEmpty ? null : portal,
      'notes': _notes.text,
    };
    try {
      Navigator.of(context).pop(sourceFromJson(json));
    } on SourceFormatException catch (error) {
      setState(() => _error = _readable(error.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      title: Text(widget.source == null ? 'Add source' : 'Edit source'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                'Name',
                _name,
                key: const Key('source-name'),
                autofocus: true,
              ),
              _field(
                'Base URLs, one per line',
                _urls,
                key: const Key('source-urls'),
                hint: 'http://10.0.0.5/Movies/',
                lines: 3,
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<SourceType>(
                      key: const Key('source-type'),
                      isExpanded: true,
                      initialValue: _type,
                      decoration: _decoration('Server type'),
                      items: [
                        for (final type in SourceType.values)
                          DropdownMenuItem(
                            value: type,
                            child: Text(sourceTypeLabel(type)),
                          ),
                      ],
                      onChanged: (type) => _type = type ?? _type,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<SourceCategory>(
                      key: const Key('source-category'),
                      isExpanded: true,
                      initialValue: _category,
                      decoration: _decoration('Content'),
                      items: [
                        for (final category in SourceCategory.values)
                          DropdownMenuItem(
                            value: category,
                            child: Text(sourceCategoryLabel(category)),
                          ),
                      ],
                      onChanged: (category) =>
                          _category = category ?? _category,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _field('Provider (optional)', _provider)),
                  const SizedBox(width: 12),
                  Expanded(child: _field('ISP (optional)', _isp)),
                ],
              ),
              _field('Portal page (optional)', _portal, hint: 'http://…'),
              _field('Notes (optional)', _notes, lines: 2),
              if (error != null)
                Text(
                  error,
                  key: const Key('source-form-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('source-save'),
          onPressed: _save,
          child: Text(widget.source == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    Key? key,
    String? hint,
    int lines = 1,
    bool autofocus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: key,
        controller: controller,
        autofocus: autofocus,
        autocorrect: false,
        enableSuggestions: false,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 6,
        // Enter saves from a one-line field; in a list it starts a new line.
        onSubmitted: lines == 1 ? (_) => _save() : null,
        decoration: _decoration(label).copyWith(hintText: hint),
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      );
}

/// Turns the parser's `source.baseUrls[1]: …` into words for the form.
String _readable(String message) {
  final match = _fieldMessage.firstMatch(message);
  if (match == null) return message;
  final index = match[2];
  final field = switch (match[1]) {
    'name' => 'Name',
    'baseUrls' when index != null => 'Base URL on line ${int.parse(index) + 1}',
    'baseUrls' => 'Base URLs',
    'provider' => 'Provider',
    'isp' => 'ISP',
    'portalUrl' => 'Portal page',
    'notes' => 'Notes',
    final other => other,
  };
  return '$field: ${match[3]}';
}

final _fieldMessage = RegExp(r'^source\.(\w+)(?:\[(\d+)\])?: (.*)$');
