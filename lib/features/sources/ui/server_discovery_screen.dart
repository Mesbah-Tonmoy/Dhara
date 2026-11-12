import 'dart:async';
import 'dart:io';

import 'package:dhara/features/player/widgets/glass.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_list.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/features/sources/source_tester.dart';
import 'package:dhara/features/sources/ui/source_form_dialog.dart';
import 'package:dhara/features/sources/ui/source_list_files.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/material.dart';

enum _Filter {
  all('All'),
  reachable('Reachable'),
  unreachable('Unreachable'),
  enabled('Enabled');

  const _Filter(this.label);

  final String label;

  bool shows(SourceStatus status, {required bool enabled}) => switch (this) {
        all => true,
        reachable =>
          status == SourceStatus.readable || status == SourceStatus.unreadable,
        unreachable => status == SourceStatus.unreachable,
        _Filter.enabled => enabled,
      };
}

enum _RowAction { test, edit, remove }

/// Server Discovery, the BDIX Tester: every known source with what the
/// last test found, and the tools to test, enable, add, edit, remove,
/// import and export sources.
///
/// Every piece of server-supplied text (names, samples, titles) is shown
/// through plain `Text` widgets only.
class ServerDiscoveryScreen extends StatefulWidget {
  const ServerDiscoveryScreen({
    super.key,
    this.files = const SourceListFiles(),
  });

  /// Where import and export files come from and go to.
  final SourceListFiles files;

  @override
  State<ServerDiscoveryScreen> createState() => _ServerDiscoveryScreenState();
}

class _ServerDiscoveryScreenState extends State<ServerDiscoveryScreen> {
  var _filter = _Filter.all;

  SourceTestController get _tests => SourcesScope.read(context);
  SourceStore get _store => _tests.store;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs a change to the source list and says so if it could not be
  /// applied or saved.
  Future<void> _change(Future<void> Function() change) async {
    try {
      await change();
    } on SourceFormatException catch (error) {
      _say(error.message);
    } on FileSystemException {
      _say('Could not save to disk. The change lasts until the app closes.');
    }
  }

  void _toggleTesting() =>
      unawaited(_tests.isTesting ? _tests.cancel() : _tests.testAll());

  Future<void> _enableAllReachable() async {
    int enabledCount() =>
        _store.sources.where((s) => _store.isEnabled(s.id)).length;
    final before = enabledCount();
    await _change(_tests.enableAllReadable);
    final added = enabledCount() - before;
    _say(
      added == 0
          ? 'No more reachable servers to enable. Run "Test all" first.'
          : 'Enabled $added more ${added == 1 ? 'server' : 'servers'}.',
    );
  }

  Set<String> get _ids => {for (final source in _store.sources) source.id};

  Future<void> _add() async {
    final source = await showSourceFormDialog(context, takenIds: _ids);
    if (source != null) await _change(() => _store.add(source));
  }

  Future<void> _edit(Source source) async {
    final edited = await showSourceFormDialog(
      context,
      source: source,
      takenIds: _ids,
    );
    if (edited != null) await _change(() => _store.update(edited));
  }

  Future<void> _remove(Source source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove source?'),
        content: Text(
          '"${source.name}" will leave your list and will no longer be used '
          'for search or playback.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-remove'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await _change(() => _store.remove(source.id));
  }

  Future<void> _import() async {
    final List<Source> sources;
    try {
      final text = await widget.files.pickAndRead();
      if (text == null) return;
      sources = parseSourceList(text);
    } on SourceFormatException catch (error) {
      _say('Nothing was imported. ${error.message}');
      return;
    }
    final preview = _store.previewImport(sources);
    if (preview.changesNothing) {
      _say('Nothing new: your list already has everything in that file.');
      return;
    }
    if (!mounted) return;
    final added = preview.added.length;
    final changed = preview.changed.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import sources?'),
        content: Text(
          '$added new and $changed changed '
          '(${preview.unchanged} already in your list).\n\n'
          'Imported servers stay off until you test and enable them. A '
          'changed server is switched off until it is tested again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-import'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await _change(() => _store.importSources(sources));
      _say('Imported: $added added, $changed replaced.');
    }
  }

  Future<void> _export() async {
    try {
      final path = await widget.files.save(_store.exportJson());
      if (path != null) _say('Saved ${_store.sources.length} sources.');
    } on FileSystemException {
      _say('The file could not be written.');
    }
  }

  void _onRowAction(Source source, _RowAction action) {
    switch (action) {
      case _RowAction.test:
        unawaited(_tests.test([source]));
      case _RowAction.edit:
        unawaited(_edit(source));
      case _RowAction.remove:
        unawaited(_remove(source));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tests = SourcesScope.of(context);
    final store = tests.store;
    final shown = [
      for (final source in store.sources)
        if (_filter.shows(
          tests.statusOf(source.id),
          enabled: store.isEnabled(source.id),
        ))
          source,
    ];

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) {
          // ISP and content columns need room; drop them on small windows.
          final wide = box.maxWidth >= 1180;
          final gutter = box.maxWidth >= 900 ? 40.0 : 20.0;
          final sides = EdgeInsets.symmetric(horizontal: gutter);
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: sides.copyWith(top: 28),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(
                        tests: tests,
                        onTest: _toggleTesting,
                        onEnableAll: _enableAllReachable,
                        onAdd: _add,
                        onImport: _import,
                        onExport: _export,
                      ),
                      const SizedBox(height: 22),
                      _Stats(
                          tests: tests, columns: box.maxWidth >= 860 ? 4 : 2),
                      const SizedBox(height: 18),
                      _ProgressBar(tests: tests),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final filter in _Filter.values)
                            DharaChip(
                              key: Key('filter-${filter.name}'),
                              selected: filter == _filter,
                              onTap: () => setState(() => _filter = filter),
                              child: Text(filter.label),
                            ),
                          const SizedBox(width: 8),
                          const Text(
                            'Enabled servers are re-tested weekly, when the '
                            'app starts.',
                            style: TextStyle(
                              fontSize: 12,
                              color: DharaColors.text3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _TableHead(wide: wide),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: sides,
                sliver: shown.isEmpty
                    ? const SliverToBoxAdapter(child: _EmptyRow())
                    : SliverList.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, index) {
                          final source = shown[index];
                          return _SourceRow(
                            key: ValueKey(source.id),
                            source: source,
                            tests: tests,
                            wide: wide,
                            isLast: index == shown.length - 1,
                            onEnabled: (enabled) => _change(
                              () => _store.setEnabled(
                                [source.id],
                                enabled: enabled,
                              ),
                            ),
                            onAction: (action) => _onRowAction(source, action),
                          );
                        },
                      ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 36)),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.tests,
    required this.onTest,
    required this.onEnableAll,
    required this.onAdd,
    required this.onImport,
    required this.onExport,
  });

  final SourceTestController tests;
  final VoidCallback onTest;
  final VoidCallback onEnableAll;
  final VoidCallback onAdd;
  final VoidCallback onImport;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 16,
      runSpacing: 14,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Server Discovery',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'BDIX Tester: checks every source in this list from '
                      'your connection. Only these addresses are contacted. '
                      'No port or IP-range scanning.',
                      style: TextStyle(fontSize: 13, color: DharaColors.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DharaPillButton(
              key: const Key('test-all'),
              primary: true,
              icon:
                  tests.isTesting ? Icons.stop_rounded : Icons.refresh_rounded,
              label: tests.isTesting
                  ? 'Stop · ${tests.done} / ${tests.total}'
                  : 'Test all',
              onPressed: onTest,
            ),
            DharaPillButton(
              key: const Key('enable-all'),
              icon: Icons.check_rounded,
              label: 'Enable all reachable',
              onPressed: onEnableAll,
            ),
            DharaPillButton(
              key: const Key('add-source'),
              icon: Icons.add_rounded,
              label: 'Add source',
              onPressed: onAdd,
            ),
            DharaPillButton(
              key: const Key('import-sources'),
              icon: Icons.file_upload_outlined,
              label: 'Import',
              onPressed: onImport,
            ),
            DharaPillButton(
              key: const Key('export-sources'),
              icon: Icons.file_download_outlined,
              label: 'Export',
              onPressed: onExport,
            ),
          ],
        ),
      ],
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.tests, required this.columns});

  final SourceTestController tests;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final store = tests.store;
    final sources = store.sources;
    var reachable = 0;
    var readable = 0;
    Source? fastest;
    Duration? fastestPing;
    for (final source in sources) {
      final status = tests.statusOf(source.id);
      if (status == SourceStatus.readable) readable++;
      if (status != SourceStatus.readable &&
          status != SourceStatus.unreadable) {
        continue;
      }
      reachable++;
      final ping = tests.pingOf(source.id);
      if (ping != null && (fastestPing == null || ping < fastestPing)) {
        fastest = source;
        fastestPing = ping;
      }
    }
    final types = {for (final source in sources) source.type}.length;
    final enabled = sources.where((s) => store.isEnabled(s.id)).length;

    final cards = [
      _StatCard(
        label: 'Candidates',
        value: '${sources.length}',
        note: '$types server ${types == 1 ? 'type' : 'types'}',
      ),
      _StatCard(
        label: 'Reachable',
        value: '$reachable',
        valueColor: DharaColors.good,
        note: '$readable the app can read',
      ),
      _StatCard(
        label: 'Enabled',
        value: '$enabled',
        note: 'used for search and playback',
      ),
      _StatCard(
        label: 'Fastest',
        value: fastestPing == null ? '–' : '${fastestPing.inMilliseconds} ms',
        note: fastest?.name ?? 'no server reachable',
      ),
    ];
    return Column(
      children: [
        for (var start = 0; start < cards.length; start += columns) ...[
          if (start > 0) const SizedBox(height: 14),
          Row(
            children: [
              for (var i = start; i < start + columns; i++) ...[
                if (i > start) const SizedBox(width: 14),
                Expanded(child: cards[i]),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.note,
    this.valueColor = DharaColors.text,
  });

  final String label;
  final String value;
  final String note;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: DharaColors.surface,
        borderRadius: BorderRadius.circular(DharaRadii.md),
        border: Border.all(color: DharaColors.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeading(label),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: DharaFonts.display,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: valueColor,
            ),
          ),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: DharaColors.text2),
          ),
        ],
      ),
    );
  }
}

/// A thin bar that fills up while a test run is going.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.tests});

  final SourceTestController tests;

  @override
  Widget build(BuildContext context) {
    final fraction = tests.total == 0 ? 0.0 : tests.done / tests.total;
    return AnimatedOpacity(
      opacity: tests.isTesting ? 1 : 0,
      duration: DharaMotion.base,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 3,
          child: ColoredBox(
            color: DharaColors.surface2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedFractionallySizedBox(
                duration: DharaMotion.base,
                widthFactor: fraction.clamp(0, 1).toDouble(),
                heightFactor: 1,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: DharaColors.accentGradient,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Column widths shared by the table head and its rows.
const _switchWidth = 62.0;
const _typeWidth = 124.0;
const _contentWidth = 76.0;
const _statusWidth = 124.0;
const _pingWidth = 70.0;
const _menuWidth = 40.0;
const _cellGap = SizedBox(width: 14);

/// Lays out one line of the table: the same columns for head and rows.
class _Cells extends StatelessWidget {
  const _Cells({
    required this.wide,
    required this.toggle,
    required this.server,
    required this.type,
    required this.content,
    required this.isp,
    required this.status,
    required this.ping,
    required this.sample,
    required this.menu,
  });

  final bool wide;
  final Widget toggle;
  final Widget server;
  final Widget type;
  final Widget content;
  final Widget isp;
  final Widget status;
  final Widget ping;
  final Widget sample;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: _switchWidth, child: toggle),
        Expanded(flex: 30, child: server),
        _cellGap,
        SizedBox(width: _typeWidth, child: type),
        if (wide) ...[
          _cellGap,
          SizedBox(width: _contentWidth, child: content),
          _cellGap,
          Expanded(flex: 16, child: isp),
        ],
        _cellGap,
        SizedBox(width: _statusWidth, child: status),
        _cellGap,
        SizedBox(width: _pingWidth, child: ping),
        _cellGap,
        Expanded(flex: 28, child: sample),
        SizedBox(width: _menuWidth, child: menu),
      ],
    );
  }
}

class _TableHead extends StatelessWidget {
  const _TableHead({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 11, 8, 11),
      decoration: const BoxDecoration(
        color: DharaColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DharaRadii.md),
        ),
      ),
      child: _Cells(
        wide: wide,
        toggle: const PanelHeading('On'),
        server: const PanelHeading('Server'),
        type: const PanelHeading('Type'),
        content: const PanelHeading('Content'),
        isp: const PanelHeading('ISP'),
        status: const PanelHeading('Status'),
        ping: const PanelHeading('Ping'),
        sample: const PanelHeading('Sample found'),
        menu: const SizedBox.shrink(),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 44),
      decoration: _rowDecoration(isLast: true),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dns_outlined, color: DharaColors.text3, size: 30),
          SizedBox(height: 8),
          Text(
            'No servers in this view',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _rowDecoration({required bool isLast}) => BoxDecoration(
      color: DharaColors.surface,
      border: const Border(top: BorderSide(color: DharaColors.stroke)),
      borderRadius: isLast
          ? const BorderRadius.vertical(
              bottom: Radius.circular(DharaRadii.md),
            )
          : null,
    );

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    super.key,
    required this.source,
    required this.tests,
    required this.wide,
    required this.isLast,
    required this.onEnabled,
    required this.onAction,
  });

  final Source source;
  final SourceTestController tests;
  final bool wide;
  final bool isLast;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<_RowAction> onAction;

  @override
  Widget build(BuildContext context) {
    final id = source.id;
    final status = tests.statusOf(id);
    final result = tests.resultOf(id);
    final ping = tests.pingOf(id);
    final dead = status == SourceStatus.unreachable;
    final plain = TextStyle(
      fontSize: 13,
      color: dead ? DharaColors.text3 : DharaColors.text2,
    );
    final more = source.baseUrls.length - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: _rowDecoration(isLast: isLast),
      child: DefaultTextStyle.merge(
        style: plain,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        child: _Cells(
          wide: wide,
          toggle: Align(
            alignment: Alignment.centerLeft,
            child: Transform.scale(
              scale: .78,
              alignment: Alignment.centerLeft,
              child: Semantics(
                label: 'Enable ${source.name}',
                child: Switch(
                  key: Key('enable-$id'),
                  value: tests.store.isEnabled(id),
                  onChanged: onEnabled,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  thumbColor: const WidgetStatePropertyAll(Colors.white),
                  trackColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? DharaColors.accent
                        : DharaColors.surface2,
                  ),
                  trackOutlineColor: const WidgetStatePropertyAll(
                    DharaColors.strokeStrong,
                  ),
                ),
              ),
            ),
          ),
          server: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                source.name,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: dead ? DharaColors.text2 : DharaColors.text,
                ),
              ),
              Text(
                '${source.baseUrls.first}${more > 0 ? '  +$more more' : ''}',
                style:
                    const TextStyle(fontSize: 11.5, color: DharaColors.text3),
              ),
            ],
          ),
          type: _TypeTag(source: source, detected: result?.detectedType),
          content: Text(sourceCategoryLabel(source.category)),
          isp: Text(source.isp ?? source.provider ?? '–'),
          status: _StatusLabel(
            status: status,
            isWebsite:
                (result?.detectedType ?? source.type) == SourceType.customSite,
          ),
          ping: ping == null || dead
              ? const Text('–')
              : Text(
                  '${ping.inMilliseconds} ms',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: switch (ping.inMilliseconds) {
                      < 60 => DharaColors.good,
                      < 200 => DharaColors.warn,
                      _ => DharaColors.bad,
                    },
                  ),
                ),
          sample: Text(
            _sampleText(status, result, tests.store.healthOf(id)),
            style: const TextStyle(fontSize: 12),
          ),
          menu: PopupMenuButton<_RowAction>(
            key: Key('menu-$id'),
            tooltip: 'More',
            padding: EdgeInsets.zero,
            iconSize: 20,
            icon: const Icon(Icons.more_horiz_rounded),
            // Keeps the rows compact: the default 48 px target sets their
            // height otherwise.
            style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: WidgetStatePropertyAll(Size.square(34)),
            ),
            onSelected: onAction,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _RowAction.test,
                enabled: !tests.isTesting,
                child: const Text('Test now'),
              ),
              const PopupMenuItem(value: _RowAction.edit, child: Text('Edit')),
              const PopupMenuItem(
                value: _RowAction.remove,
                child: Text('Remove'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the "Sample found" column says about a source.
String _sampleText(
  SourceStatus status,
  SourceTestResult? result,
  SourceHealth? health,
) {
  if (status == SourceStatus.testing) return 'Waiting for a response…';
  if (result == null) {
    return health == null ? '–' : 'Checked ${_when(health.checkedAt)}';
  }
  for (final url in result.urls) {
    if (!url.readable) continue;
    final count = url.entryCount;
    return [
      if (count != null) '$count ${count == 1 ? 'item' : 'items'}',
      ...url.sample,
    ].join(' · ');
  }
  for (final url in result.urls) {
    final problem = url.problem;
    if (problem != null) return problem;
  }
  // Answered and is fine, but it is a kind of site without an adapter.
  final title = result.urls.expand((url) => url.sample).firstOrNull;
  return title == null
      ? 'A website the app cannot read yet'
      : 'Website: $title';
}

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _when(DateTime time) {
  final minute = '${time.minute}'.padLeft(2, '0');
  return '${time.day} ${_monthNames[time.month - 1]}, ${time.hour}:$minute';
}

class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.source, required this.detected});

  final Source source;

  /// What the last test found the server to be, if it was tested.
  final SourceType? detected;

  @override
  Widget build(BuildContext context) {
    final detected = this.detected;
    final differs = detected != null && detected != source.type;
    final tag = Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DharaColors.surface2,
          borderRadius: BorderRadius.circular(6),
          border: differs ? Border.all(color: DharaColors.warn) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            sourceTypeLabel(detected ?? source.type),
            style: const TextStyle(fontSize: 11.5, color: DharaColors.text),
          ),
        ),
      ),
    );
    if (!differs) return tag;
    return Tooltip(
      message: 'The test found ${sourceTypeLabel(detected)}; the list says '
          '${sourceTypeLabel(source.type)}. Edit the source to correct it.',
      child: tag,
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status, required this.isWebsite});

  final SourceStatus status;

  /// A site without an adapter, as opposed to a server that had a problem.
  final bool isWebsite;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      SourceStatus.untested => ('Not tested', DharaColors.text3),
      SourceStatus.testing => ('Testing…', DharaColors.text2),
      SourceStatus.readable => ('Reachable', DharaColors.good),
      SourceStatus.unreadable => (
          isWebsite ? 'No adapter' : 'Problem',
          DharaColors.warn,
        ),
      SourceStatus.unreachable => ('Unreachable', DharaColors.bad),
    };
    return Row(
      children: [
        if (status == SourceStatus.testing)
          const SizedBox.square(
            dimension: 11,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: DharaColors.accent2,
            ),
          )
        else
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
