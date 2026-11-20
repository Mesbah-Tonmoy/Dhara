import 'dart:async';
import 'dart:io';

import 'package:dhara/features/sources/portal_links.dart';
import 'package:dhara/features/sources/source.dart';
import 'package:dhara/features/sources/source_list.dart';
import 'package:dhara/features/sources/source_store.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/features/sources/source_tester.dart';
import 'package:dhara/features/sources/ui/linked_servers_dialog.dart';
import 'package:dhara/features/sources/ui/source_form_dialog.dart';
import 'package:dhara/features/sources/ui/source_list_files.dart';
import 'package:dhara/shell/page_bleed.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/chips.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/page_parts.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:dhara/widgets/toast.dart';
import 'package:flutter/material.dart';

enum _Filter {
  all('All'),
  reachable('Reachable'),
  readable('Readable'),
  unreachable('Unreachable'),
  untested('Never tested'),
  enabled('Enabled');

  const _Filter(this.label);

  final String label;

  bool shows(SourceStatus status, {required bool enabled}) => switch (this) {
    all => true,
    reachable =>
      status == SourceStatus.readable || status == SourceStatus.unreadable,
    readable => status == SourceStatus.readable,
    unreachable => status == SourceStatus.unreachable,
    untested => status == SourceStatus.untested,
    _Filter.enabled => enabled,
  };
}

enum _RowAction { test, links, edit, remove }

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

  /// What is typed into the search field, and its words in lower case.
  final _search = TextEditingController();
  var _words = const <String>[];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) => setState(() {
    _words = [
      for (final word in text.toLowerCase().split(RegExp(r'\s+')))
        if (word.isNotEmpty) word,
    ];
  });

  /// Whether every word typed is somewhere in what the list says of
  /// [source]: its name, its operator and ISP, or one of its addresses.
  bool _matches(Source source) {
    if (_words.isEmpty) return true;
    final text = [
      source.name,
      source.provider ?? '',
      source.isp ?? '',
      for (final url in source.baseUrls) url.toString(),
    ].join('\n').toLowerCase();
    return _words.every(text.contains);
  }

  SourceTestController get _tests => SourcesScope.read(context);
  SourceStore get _store => _tests.store;

  void _say(String message) {
    if (!mounted) return;
    // Longer than a passing note: these say what was done to the list, or
    // what went wrong.
    ToastHost.show(context, message, showFor: const Duration(seconds: 5));
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

  /// Switches a source on or off. A website the app has no adapter for can
  /// be switched on too, but nothing of it reaches the library: said here,
  /// as nothing else on this screen would show it.
  Future<void> _setEnabled(Source source, bool enabled) async {
    await _change(() => _store.setEnabled([source.id], enabled: enabled));
    if (enabled && source.type == SourceType.customSite) {
      _say(
        '${source.name} is a website, which Dhara cannot read yet. '
        'Nothing of it will be in your library.',
      );
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
          DharaButton(
            label: 'Cancel',
            small: true,
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          DharaButton(
            key: const Key('confirm-remove'),
            label: 'Remove',
            small: true,
            danger: true,
            onPressed: () => Navigator.of(context).pop(true),
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
          DharaButton(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          DharaButton(
            key: const Key('confirm-import'),
            label: 'Import',
            small: true,
            style: DharaButtonStyle.primary,
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
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

  /// Lists the servers the website [source] links to, as its last test
  /// found them, and adds the one the user picks: through the same form
  /// as any new source, so nothing is added unseen. It is not tested or
  /// switched on by that.
  Future<void> _showLinks(Source source) async {
    final links = _linksOf(_tests.resultOf(source.id));
    if (links.isEmpty) return;
    final link = await showLinkedServersDialog(
      context,
      source: source,
      links: links,
      sources: _store.sources,
    );
    if (link == null || !mounted) return;
    final added = await showSourceFormDialog(
      context,
      takenIds: _ids,
      suggested: Source(
        id: 'suggested',
        name: link.label == link.url.host
            ? link.url.host
            : '${source.name}: ${link.label}',
        type: SourceType.directoryListing,
        category: source.category,
        baseUrls: [link.url],
        provider: source.provider,
        isp: source.isp,
        portalUrl: source.baseUrls.first,
        notes: 'Linked from ${source.name}.',
      ),
    );
    if (added == null) return;
    await _change(() => _store.add(added));
    _say(
      '${added.name} is in the list. "Test now" in its menu shows what '
      'kind of server it is.',
    );
  }

  void _onRowAction(Source source, _RowAction action) {
    switch (action) {
      case _RowAction.test:
        unawaited(_tests.test([source]));
      case _RowAction.links:
        unawaited(_showLinks(source));
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
        if (_matches(source) &&
            _filter.shows(
              tests.statusOf(source.id),
              enabled: store.isEnabled(source.id),
            ))
          source,
    ];

    return ColoredBox(
      key: const Key('discovery'),
      color: DharaColors.bg,
      // The row menus and tooltips are Material's.
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, box) {
            const sides = EdgeInsets.only(
              left: PageInsets.contentLeft,
              right: DharaLayout.pageRight,
            );
            final room = box.maxWidth - sides.horizontal;
            // ISP and content columns need room; drop them on small windows.
            final wide = room >= 68 * rem;
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: sides.copyWith(top: 1.8 * rem),
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
                        const SizedBox(height: 1.4 * rem),
                        _Stats(tests: tests, columns: room >= 48 * rem ? 4 : 2),
                        const SizedBox(height: 1.2 * rem),
                        _ProgressBar(tests: tests),
                        const SizedBox(height: rem),
                        Wrap(
                          spacing: .5 * rem,
                          runSpacing: .5 * rem,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 17 * rem,
                              child: DharaField(
                                key: const Key('discovery-search'),
                                controller: _search,
                                icon: DharaIcons.search,
                                hint: 'Name, ISP or address',
                                onChanged: _onSearch,
                              ),
                            ),
                            for (final filter in _Filter.values)
                              PillChip(
                                key: Key('filter-${filter.name}'),
                                label: filter.label,
                                small: true,
                                selected: filter == _filter,
                                onPressed: () =>
                                    setState(() => _filter = filter),
                              ),
                            const SizedBox(width: .5 * rem),
                            const Text(
                              'Enabled servers are re-tested weekly, when the '
                              'app starts.',
                              style: TextStyle(
                                fontFamily: DharaFonts.ui,
                                fontSize: DharaType.xs,
                                color: DharaColors.text3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: rem),
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
                              onEnabled: (enabled) =>
                                  _setEnabled(source, enabled),
                              onAction: (action) =>
                                  _onRowAction(source, action),
                            );
                          },
                        ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: DharaSpace.s7),
                ),
              ],
            );
          },
        ),
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
      spacing: rem,
      runSpacing: rem,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 40 * rem),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Server Discovery',
                key: Key('discovery-heading'),
                style: TextStyle(
                  fontFamily: DharaFonts.display,
                  fontSize: DharaType.xxl,
                  fontWeight: DharaType.bold,
                  letterSpacing: -.03 * DharaType.xxl,
                  height: 1.1,
                  color: DharaColors.text,
                ),
              ),
              SizedBox(height: .3 * rem),
              Text(
                'BDIX Tester: checks every source in this list from '
                'your connection. Only these addresses are contacted. '
                'No port or IP-range scanning.',
                style: TextStyle(
                  fontFamily: DharaFonts.ui,
                  fontSize: DharaType.sm,
                  height: 1.45,
                  color: DharaColors.text2,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: .5 * rem,
          runSpacing: .5 * rem,
          children: [
            DharaButton(
              key: const Key('test-all'),
              style: DharaButtonStyle.primary,
              small: true,
              icon: tests.isTesting ? DharaIcons.stop : DharaIcons.refresh,
              label: tests.isTesting
                  ? 'Stop · ${tests.done} / ${tests.total}'
                  : 'Test all',
              onPressed: onTest,
            ),
            DharaButton(
              key: const Key('enable-all'),
              small: true,
              icon: DharaIcons.check,
              label: 'Enable all reachable',
              onPressed: onEnableAll,
            ),
            DharaButton(
              key: const Key('add-source'),
              small: true,
              icon: DharaIcons.add,
              label: 'Add source',
              onPressed: onAdd,
            ),
            DharaButton(
              key: const Key('import-sources'),
              small: true,
              icon: DharaIcons.importFile,
              label: 'Import',
              onPressed: onImport,
            ),
            DharaButton(
              key: const Key('export-sources'),
              small: true,
              icon: DharaIcons.exportFile,
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
      _Stat(
        label: 'Candidates',
        value: '${sources.length}',
        note: '$types server ${types == 1 ? 'type' : 'types'}',
      ),
      _Stat(
        label: 'Reachable',
        value: '$reachable',
        valueColor: DharaColors.good,
        note: '$readable the app can read',
      ),
      _Stat(
        label: 'Enabled',
        value: '$enabled',
        note: 'used for search and playback',
      ),
      _Stat(
        label: 'Fastest',
        value: fastestPing == null ? '–' : '${fastestPing.inMilliseconds} ms',
        note: fastest?.name ?? 'no server reachable',
      ),
    ];
    return Column(
      children: [
        for (var start = 0; start < cards.length; start += columns) ...[
          if (start > 0) const SizedBox(height: rem),
          Row(
            children: [
              for (var i = start; i < start + columns; i++) ...[
                if (i > start) const SizedBox(width: rem),
                Expanded(child: cards[i]),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// One number about the list, with what it counts above and a note below.
class _Stat extends StatelessWidget {
  const _Stat({
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
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 1.2 * rem, vertical: rem),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeadText(label),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: DharaFonts.display,
              fontSize: DharaType.xxl,
              fontWeight: DharaType.bold,
              height: 1.2,
              color: valueColor,
            ),
          ),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: DharaFonts.ui,
              fontSize: DharaType.xs,
              color: DharaColors.text2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The small spaced capitals over a stat and over the table's columns.
class _HeadText extends StatelessWidget {
  const _HeadText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontFamily: DharaFonts.ui,
        fontSize: DharaType.xs,
        letterSpacing: .12 * DharaType.xs,
        color: DharaColors.text3,
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
    final duration = motion(context, DharaMotion.base);
    return AnimatedOpacity(
      opacity: tests.isTesting ? 1 : 0,
      duration: duration,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 3,
          child: ColoredBox(
            color: DharaColors.surface2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedFractionallySizedBox(
                duration: duration,
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
const _switchWidth = 3.6 * rem;
const _typeWidth = 8.2 * rem;
const _contentWidth = 5 * rem;
const _statusWidth = 7.6 * rem;
const _pingWidth = 4.6 * rem;
const _menuWidth = 2.6 * rem;
const _cellGap = SizedBox(width: rem);
const _rowSides = EdgeInsets.only(left: 1.1 * rem, right: .5 * rem);

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
      padding: _rowSides.copyWith(top: .7 * rem, bottom: .7 * rem),
      decoration: const BoxDecoration(
        color: DharaColors.surface,
        border: Border(
          top: BorderSide(color: DharaColors.stroke),
          left: BorderSide(color: DharaColors.stroke),
          right: BorderSide(color: DharaColors.stroke),
        ),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DharaRadii.lg),
        ),
      ),
      child: _Cells(
        wide: wide,
        toggle: const _HeadText('On'),
        server: const _HeadText('Server'),
        type: const _HeadText('Type'),
        content: const _HeadText('Content'),
        isp: const _HeadText('ISP'),
        status: const _HeadText('Status'),
        ping: const _HeadText('Ping'),
        sample: const _HeadText('Sample found'),
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
      padding: const EdgeInsets.symmetric(vertical: 3 * rem),
      decoration: _rowDecoration(isLast: true),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(DharaIcons.servers, color: DharaColors.text3, size: 2 * rem),
          SizedBox(height: .5 * rem),
          Text(
            'No servers in this view',
            style: TextStyle(
              fontFamily: DharaFonts.ui,
              fontSize: DharaType.md,
              fontWeight: DharaType.semibold,
              color: DharaColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// The ground of a row: the table is one card, its rows parted by a line.
BoxDecoration _rowDecoration({required bool isLast, bool lit = false}) {
  const line = BorderSide(color: DharaColors.stroke);
  final corners = isLast
      ? const BorderRadius.vertical(bottom: Radius.circular(DharaRadii.lg))
      : null;
  return BoxDecoration(
    color: lit ? DharaColors.surface2 : DharaColors.surface,
    // A border with rounded corners has to be the same on every side.
    border: isLast
        ? Border.all(color: DharaColors.stroke)
        : const Border(top: line, left: line, right: line),
    borderRadius: corners,
  );
}

class _SourceRow extends StatefulWidget {
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
  State<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends State<_SourceRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final tests = widget.tests;
    final id = source.id;
    final status = tests.statusOf(id);
    final result = tests.resultOf(id);
    final ping = tests.pingOf(id);
    final dead = status == SourceStatus.unreachable;
    final plain = TextStyle(
      fontFamily: DharaFonts.ui,
      fontSize: DharaType.sm,
      color: dead ? DharaColors.text3 : DharaColors.text2,
    );
    final more = source.baseUrls.length - 1;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // Not animated: a row that becomes the last one changes the shape of
      // its border, which cannot be drawn half-way.
      child: Container(
        padding: _rowSides.copyWith(top: .55 * rem, bottom: .55 * rem),
        decoration: _rowDecoration(isLast: widget.isLast, lit: _hovered),
        child: DefaultTextStyle.merge(
          style: plain,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          child: _Cells(
            wide: widget.wide,
            toggle: Align(
              alignment: Alignment.centerLeft,
              child: DharaSwitch(
                key: Key('enable-$id'),
                label: 'Enable ${source.name}',
                value: tests.store.isEnabled(id),
                onChanged: widget.onEnabled,
              ),
            ),
            server: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.name,
                  style: TextStyle(
                    fontWeight: DharaType.semibold,
                    color: dead ? DharaColors.text2 : DharaColors.text,
                  ),
                ),
                Text(
                  '${source.baseUrls.first}${more > 0 ? '  +$more more' : ''}',
                  style: const TextStyle(
                    fontFamily: DharaFonts.mono,
                    fontFamilyFallback: DharaFonts.monoFallback,
                    fontSize: DharaType.xs,
                    color: DharaColors.text3,
                  ),
                ),
              ],
            ),
            type: _TypeTag(source: source, detected: result?.detectedType),
            content: Text(sourceCategoryLabel(source.category)),
            isp: Text(source.isp ?? source.provider ?? '–'),
            status: _StatusLabel(
              status: status,
              isWebsite:
                  (result?.detectedType ?? source.type) ==
                  SourceType.customSite,
            ),
            ping: ping == null || dead
                ? const Text('–')
                : Text(
                    '${ping.inMilliseconds} ms',
                    style: TextStyle(
                      fontWeight: DharaType.semibold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: switch (ping.inMilliseconds) {
                        < 60 => DharaColors.good,
                        < 200 => DharaColors.warn,
                        _ => DharaColors.bad,
                      },
                    ),
                  ),
            sample: Text(
              _sampleText(status, result, tests.store.healthOf(id)),
              style: const TextStyle(fontSize: DharaType.xs),
            ),
            menu: PopupMenuButton<_RowAction>(
              key: Key('menu-$id'),
              tooltip: 'More',
              padding: EdgeInsets.zero,
              iconSize: 1.3 * rem,
              icon: const Icon(DharaIcons.more, color: DharaColors.text2),
              // Keeps the rows compact: the default 48 px target sets their
              // height otherwise.
              style: const ButtonStyle(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                minimumSize: WidgetStatePropertyAll(Size.square(2.2 * rem)),
              ),
              onSelected: widget.onAction,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _RowAction.test,
                  enabled: !tests.isTesting,
                  child: const Text('Test now'),
                ),
                // A website that turned out to be a page of links.
                if (_linksOf(result).isNotEmpty)
                  const PopupMenuItem(
                    value: _RowAction.links,
                    child: Text('Linked servers'),
                  ),
                const PopupMenuItem(
                  value: _RowAction.edit,
                  child: Text('Edit'),
                ),
                const PopupMenuItem(
                  value: _RowAction.remove,
                  child: Text('Remove'),
                ),
              ],
            ),
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
  final links = _linksOf(result).length;
  return [
    // A front page: said first, the column is narrow. What it is good for
    // is in the row's menu.
    if (links > 0) 'Links to $links other ${links == 1 ? 'server' : 'servers'}',
    title == null ? 'A website the app cannot read yet' : 'Website: $title',
  ].join(' · ');
}

/// The other servers a tested website links to (see [portalLinks]), the
/// first of each host over all its addresses.
List<PortalLink> _linksOf(SourceTestResult? result) {
  if (result == null) return const [];
  final hosts = <String>{};
  return [
    for (final url in result.urls)
      for (final link in url.links)
        if (hosts.add('${link.url.host}:${link.url.port}')) link,
  ];
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
      child: Container(
        height: 1.4 * rem,
        padding: const EdgeInsets.symmetric(horizontal: .5 * rem),
        decoration: BoxDecoration(
          color: DharaColors.surface2,
          borderRadius: BorderRadius.circular(.35 * rem),
          border: differs ? Border.all(color: DharaColors.warn) : null,
        ),
        // As wide as its text, not as its column.
        child: Center(
          widthFactor: 1,
          child: Text(
            sourceTypeLabel(detected ?? source.type),
            style: const TextStyle(
              fontSize: DharaType.xs,
              height: 1.1,
              color: DharaColors.text,
            ),
          ),
        ),
      ),
    );
    if (!differs) return tag;
    return Tooltip(
      message:
          'The test found ${sourceTypeLabel(detected)}, which Dhara could '
          'not read; the list says ${sourceTypeLabel(source.type)}.',
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
            dimension: .8 * rem,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: DharaColors.accent2,
            ),
          )
        else
          Container(
            width: .5 * rem,
            height: .5 * rem,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: .4 * rem),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: DharaType.xs,
              fontWeight: DharaType.semibold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
