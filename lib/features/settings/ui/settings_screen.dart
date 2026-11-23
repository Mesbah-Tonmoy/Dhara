import 'dart:async';

import 'package:dhara/core/app_info.dart';
import 'package:dhara/core/settings/settings_controller.dart';
import 'package:dhara/features/metadata/tmdb_key.dart';
import 'package:dhara/features/my_list/ui/lists_screen.dart';
import 'package:dhara/features/player/widgets/seek_step_panel.dart';
import 'package:dhara/shell/page_bleed.dart';
import 'package:dhara/shell/shell_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/chips.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/logo.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:dhara/widgets/surfaces.dart';
import 'package:flutter/material.dart';

/// The parts of the Settings page, in the order they are shown.
enum SettingsGroup {
  playback('Playback'),
  appearance('Appearance'),
  keyboard('Keyboard'),

  /// The way to the tools for working on the library, which only a
  /// development build has.
  library('Library and metadata', devOnly: true),
  sources('Sources'),
  privacy('Privacy and security'),
  about('About');

  const SettingsGroup(this.label, {this.devOnly = false});

  final String label;

  /// Left out of a production build.
  final bool devOnly;
}

/// Settings: what can be changed about playback and the look, and the way
/// to Server Discovery and, in a development build, to the tools (matching,
/// the library index).
///
/// Every control here does something now and is saved as it is changed;
/// there is none whose feature is not built.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _anchors = {
    for (final group in SettingsGroup.values) group: GlobalKey(),
  };

  void _show(SettingsGroup group) {
    final target = _anchors[group]?.currentContext;
    if (target == null) return;
    unawaited(
      Scrollable.ensureVisible(
        target,
        duration: motion(context, DharaMotion.slow),
        curve: DharaMotion.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final shell = ShellScope.read(context);
    final tmdbKey = TmdbKeyScope.of(context);

    Widget group(SettingsGroup group, List<Widget> rows) => Padding(
      key: _anchors[group],
      padding: const EdgeInsets.only(bottom: 1.1 * rem),
      child: _GroupCard(
        key: Key('settings-group-${group.name}'),
        title: group.label,
        rows: rows,
      ),
    );

    final groups = <Widget>[
      group(SettingsGroup.playback, [
        _SetRow(
          label: 'Seek step back',
          hint: 'How far the back button and the ← key jump.',
          wide: true,
          control: SeekStepChoices(
            id: 'back',
            label: 'Back',
            alignment: WrapAlignment.end,
            seconds: settings.seekBackSeconds,
            onChanged: settings.setSeekBackSeconds,
          ),
        ),
        _SetRow(
          label: 'Seek step forward',
          hint: 'How far the forward button and the → key jump.',
          wide: true,
          control: SeekStepChoices(
            id: 'forward',
            label: 'Forward',
            alignment: WrapAlignment.end,
            seconds: settings.seekForwardSeconds,
            onChanged: settings.setSeekForwardSeconds,
          ),
        ),
        _SetRow(
          label: 'Preferred quality',
          hint:
              'Play takes the copy at this quality whose server answers '
              'fastest. Where a title has none at it: the nearest below, '
              'then the nearest above.',
          control: SegmentedPills<PreferredQuality>(
            key: const Key('set-quality'),
            choices: {
              for (final quality in PreferredQuality.values)
                quality: quality.label,
            },
            selected: settings.preferredQuality,
            onSelected: settings.setPreferredQuality,
          ),
        ),
        _SetRow(
          label: 'Autoplay next episode',
          hint:
              'When an episode ends, the next one starts by itself after '
              'a countdown.',
          control: DharaSwitch(
            key: const Key('set-autoplay'),
            label: 'Autoplay next episode',
            value: settings.autoplayNext,
            onChanged: settings.setAutoplayNext,
          ),
        ),
        _SetRow(
          label: 'Subtitle size',
          hint: 'Also changed in the player, while a video plays.',
          control: _Stepper(
            id: 'subtitle',
            what: 'subtitles',
            text: '${settings.subtitleScalePercent}%',
            onLess:
                settings.subtitleScalePercent >
                    SettingsController.minSubtitleScalePercent
                ? () => settings.setSubtitleScalePercent(
                    settings.subtitleScalePercent -
                        SettingsController.subtitleScaleStepPercent,
                  )
                : null,
            onMore:
                settings.subtitleScalePercent <
                    SettingsController.maxSubtitleScalePercent
                ? () => settings.setSubtitleScalePercent(
                    settings.subtitleScalePercent +
                        SettingsController.subtitleScaleStepPercent,
                  )
                : null,
          ),
        ),
        _SetRow(
          label: 'Default subtitles',
          hint:
              'A video starts with subtitles in this language if it has '
              'them, else with those its file marks as the default. They '
              'can always be changed in the player.',
          control: SegmentedPills<SubtitleLanguage>(
            key: const Key('set-subtitles'),
            choices: {
              for (final language in SubtitleLanguage.values)
                language: language.label,
            },
            selected: settings.subtitleLanguage,
            onSelected: settings.setSubtitleLanguage,
          ),
        ),
        _SetRow(
          label: 'Preferred audio',
          hint:
              'Where a video has several sound tracks, it starts with the '
              'one in this language; Original is the one the file puts '
              'first.',
          control: SegmentedPills<AudioLanguage>(
            key: const Key('set-audio'),
            choices: {
              for (final language in AudioLanguage.values)
                language: language.label,
            },
            selected: settings.audioLanguage,
            onSelected: settings.setAudioLanguage,
          ),
        ),
        _SetRow(
          label: 'Buffer size',
          hint:
              'How much of a video the player keeps in memory. More rides '
              'out a slow server; less uses less memory. Counts from the '
              'next video.',
          control: _Stepper(
            id: 'buffer',
            what: 'buffer',
            valueWidth: 5 * rem,
            text: '${settings.bufferMegabytes} MB',
            onLess:
                settings.bufferMegabytes > SettingsController.minBufferMegabytes
                ? () => settings.setBufferMegabytes(
                    settings.bufferMegabytes -
                        SettingsController.bufferStepMegabytes,
                  )
                : null,
            onMore:
                settings.bufferMegabytes < SettingsController.maxBufferMegabytes
                ? () => settings.setBufferMegabytes(
                    settings.bufferMegabytes +
                        SettingsController.bufferStepMegabytes,
                  )
                : null,
          ),
        ),
        _SetRow(
          label: 'Hardware decoding',
          hint:
              'The graphics card decodes the picture where that is known '
              'to work. Turn it off if a video shows a broken picture. '
              'Counts from the next video.',
          control: DharaSwitch(
            key: const Key('set-hwdec'),
            label: 'Hardware decoding',
            value: settings.hardwareDecoding,
            onChanged: settings.setHardwareDecoding,
          ),
        ),
      ]),
      group(SettingsGroup.appearance, [
        _SetRow(
          label: 'Interface size',
          hint:
              'Makes everything larger or smaller, on top of the size the '
              'window gives it.',
          control: SegmentedPills<int>(
            key: const Key('set-interface-size'),
            choices: {
              for (final percent in SettingsController.interfaceScales)
                percent: '$percent%',
            },
            selected: settings.interfaceScalePercent,
            onSelected: settings.setInterfaceScalePercent,
          ),
        ),
        _SetRow(
          label: 'Logo',
          hint:
              'The mark in the title bar. The icon of the program in '
              'Windows stays as it is.',
          control: _LogoChoices(
            selected: settings.logoStyle,
            onSelected: settings.setLogoStyle,
          ),
        ),
        _SetRow(
          label: 'Rotate featured titles',
          hint: 'The banner on Home moves on to the next title by itself.',
          control: DharaSwitch(
            key: const Key('set-rotate'),
            label: 'Rotate featured titles',
            value: settings.rotateFeatured,
            onChanged: settings.setRotateFeatured,
          ),
        ),
        _SetRow(
          label: 'Reduce motion',
          hint:
              'Hover zooms, fades and the banner happen at once instead '
              'of moving.',
          control: DharaSwitch(
            key: const Key('set-reduce-motion'),
            label: 'Reduce motion',
            value: settings.reduceMotion,
            onChanged: settings.setReduceMotion,
          ),
        ),
      ]),
      group(SettingsGroup.keyboard, const [
        _SetRow(
          label: 'Search',
          hint:
              'Puts the keyboard in the search field. Enter or ↓ there '
              'goes to the first result.',
          control: _Keys(['Ctrl K', '/']),
        ),
        _SetRow(
          label: 'Move around',
          hint:
              'Tab walks through everything on a page; the arrow keys '
              'move between cards, rows and buttons. Enter opens or '
              'presses.',
          control: _Keys(['Tab', '← ↑ ↓ →', 'Enter']),
        ),
        _SetRow(
          label: 'Scroll the page',
          hint: 'Wherever the keyboard is on the page.',
          control: _Keys(['PgUp', 'PgDn', 'Home', 'End']),
        ),
        _SetRow(
          label: 'Go back',
          hint: 'Esc also leaves a text field and closes a dialog.',
          control: _Keys(['Esc', 'Alt ←']),
        ),
        _SetRow(
          label: 'Play a URL',
          hint: 'Opens the box to paste a video address into.',
          control: _Keys(['Ctrl O']),
        ),
        _SetRow(
          label: 'In the player',
          hint:
              'Space plays or pauses, ← → skip by the seek steps above, '
              '↑ ↓ change the volume. F is fullscreen, M mute, S the next '
              'subtitle, N the next episode, I shows where the video '
              'comes from and how it plays. Esc leaves fullscreen, then '
              'the player.',
          control: _Keys(['Space', '← →', '↑ ↓', 'F', 'M', 'S', 'N', 'I']),
        ),
      ]),
      if (shell.devTools)
        group(SettingsGroup.library, [
          _SetRow(
            label: 'Titles and matching',
            hint: !tmdbKey.isLoaded
                ? 'The TMDB key, matching and Needs review.'
                : tmdbKey.hasKey
                ? 'A TMDB key is saved. Matching and Needs review are here '
                      'too.'
                : 'No TMDB key yet: posters and details need one. Matching '
                      'and Needs review are here too.',
            control: DharaButton(
              key: const Key('set-open-titles'),
              label: 'Open',
              icon: DharaIcons.matching,
              small: true,
              onPressed: () => shell.openOver(ShellDestination.titles),
            ),
          ),
          _SetRow(
            label: 'Library index',
            hint:
                'Reads the folders of the enabled servers, and shows how far '
                'that is.',
            control: DharaButton(
              key: const Key('set-open-library'),
              label: 'Open',
              icon: DharaIcons.library,
              small: true,
              onPressed: () => shell.openOver(ShellDestination.library),
            ),
          ),
        ]),
      group(SettingsGroup.sources, [
        _SetRow(
          label: 'Server Discovery',
          hint:
              'Tests the servers of the list from this connection, and '
              'turns them on or off.',
          control: DharaButton(
            key: const Key('set-open-discovery'),
            label: 'Open',
            icon: DharaIcons.servers,
            small: true,
            onPressed: () => shell.open(ShellDestination.discovery),
          ),
        ),
      ]),
      group(SettingsGroup.privacy, [
        const _SetRow(
          label: 'Telemetry',
          hint:
              'No analytics, no crash upload, no account. Nothing to '
              'turn off.',
          control: DharaBadge('ALWAYS OFF', style: DharaBadgeStyle.good),
        ),
        const _SetRow(
          label: 'Network',
          hint:
              'Only the enabled servers, TMDB and AniList are contacted, '
              'and only over http and https.',
          control: DharaBadge('RESTRICTED', style: DharaBadgeStyle.good),
        ),
        const _SetRow(
          label: 'Updates',
          hint:
              'The app never updates itself and starts nothing in the '
              'background.',
          control: DharaBadge('MANUAL'),
        ),
        _SetRow(
          label: 'Watch history',
          hint:
              'Kept on this PC only. Clearing it also forgets where videos '
              'were left.',
          control: DharaButton(
            key: const Key('set-clear-history'),
            label: 'Clear history',
            icon: DharaIcons.remove,
            small: true,
            danger: true,
            onPressed: () => unawaited(clearHistoryAfterAsking(context)),
          ),
        ),
      ]),
      group(SettingsGroup.about, const [
        _SetRow(
          label: 'Dhara',
          hint:
              'A personal player for BDIX media servers. It only plays; '
              'it hosts and shares nothing.',
          control: DharaBadge('VERSION $dharaVersion'),
        ),
        _SetRow(
          label: 'Player',
          hint:
              'libmpv through media_kit, inside the app: nothing else '
              'needs installing.',
          control: SizedBox.shrink(),
        ),
      ]),
    ];

    return ColoredBox(
      key: const Key('settings'),
      color: DharaColors.bg,
      child: LayoutBuilder(
        builder: (context, box) {
          final withNav = box.maxWidth >= 62 * rem;
          return Padding(
            padding: const EdgeInsets.only(
              left: PageInsets.contentLeft,
              right: DharaLayout.pageRight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 1.8 * rem),
                const Text(
                  'Settings',
                  key: Key('settings-heading'),
                  style: TextStyle(
                    fontFamily: DharaFonts.display,
                    fontSize: DharaType.xxl,
                    fontWeight: DharaType.bold,
                    letterSpacing: -.03 * DharaType.xxl,
                    height: 1.1,
                    color: DharaColors.text,
                  ),
                ),
                const SizedBox(height: .3 * rem),
                const Text(
                  'Changes are saved as you make them.',
                  style: TextStyle(
                    fontFamily: DharaFonts.ui,
                    fontSize: DharaType.sm,
                    color: DharaColors.text2,
                  ),
                ),
                const SizedBox(height: 1.4 * rem),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tab walks the list first, then the settings: each
                      // is a group of its own, or the order would jump
                      // between the two columns.
                      if (withNav)
                        SizedBox(
                          width: 13 * rem,
                          child: FocusTraversalGroup(
                            child: _Nav(
                              groups: [
                                for (final group in SettingsGroup.values)
                                  if (shell.devTools || !group.devOnly) group,
                              ],
                              onShow: _show,
                            ),
                          ),
                        ),
                      Expanded(
                        child: FocusTraversalGroup(
                          child: SingleChildScrollView(
                            key: const Key('settings-scroll'),
                            padding: const EdgeInsets.only(
                              bottom: DharaSpace.s7,
                            ),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 52 * rem,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: groups,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The list of the page's parts on its left: a click brings one into view.
class _Nav extends StatelessWidget {
  const _Nav({required this.groups, required this.onShow});

  /// The parts this build's page has.
  final List<SettingsGroup> groups;
  final ValueChanged<SettingsGroup> onShow;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(DharaRadii.sm);
    return Padding(
      padding: const EdgeInsets.only(right: 1.5 * rem),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in groups)
            Pressable(
              key: Key('settings-nav-${group.name}'),
              onPressed: () => onShow(group),
              semanticLabel: group.label,
              builder: (context, state) => FocusRing(
                visible: state.focused,
                radius: radius,
                child: AnimatedContainer(
                  duration: motion(context, DharaMotion.fast),
                  padding: const EdgeInsets.symmetric(
                    horizontal: .8 * rem,
                    vertical: .55 * rem,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    color: state.hovered ? DharaColors.surface2 : null,
                  ),
                  child: Text(
                    group.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: DharaFonts.ui,
                      fontSize: DharaType.sm,
                      fontWeight: DharaType.medium,
                      color: state.hovered
                          ? DharaColors.text
                          : DharaColors.text2,
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

/// One part of the page: a glass card with a heading and its rows.
class _GroupCard extends StatelessWidget {
  const _GroupCard({super.key, required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(
        1.4 * rem,
        1.2 * rem,
        1.4 * rem,
        .5 * rem,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: DharaFonts.display,
              fontSize: DharaType.lg,
              fontWeight: DharaType.semibold,
              letterSpacing: -.02 * DharaType.lg,
              color: DharaColors.text,
            ),
          ),
          const SizedBox(height: .4 * rem),
          for (final (index, row) in rows.indexed) ...[
            if (index > 0)
              const ColoredBox(
                color: DharaColors.stroke,
                child: SizedBox(height: 1),
              ),
            row,
          ],
        ],
      ),
    );
  }
}

/// One setting: what it is and what it does on the left, its control on
/// the right.
class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.label,
    required this.hint,
    required this.control,
    this.wide = false,
  });

  final String label;
  final String hint;
  final Widget control;

  /// The control is a row of chips that needs room and may wrap.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: .9 * rem),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: DharaFonts.ui,
                    fontSize: DharaType.md,
                    fontWeight: DharaType.semibold,
                    color: DharaColors.text,
                  ),
                ),
                const SizedBox(height: .2 * rem),
                Text(
                  hint,
                  style: const TextStyle(
                    fontFamily: DharaFonts.ui,
                    fontSize: DharaType.sm,
                    height: 1.45,
                    color: DharaColors.text2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 1.2 * rem),
          if (wide)
            Expanded(
              flex: 6,
              child: Align(alignment: Alignment.centerRight, child: control),
            )
          else
            // At the right edge, and never wider than the room there is.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 20 * rem),
              child: FittedBox(fit: BoxFit.scaleDown, child: control),
            ),
        ],
      ),
    );
  }
}

/// The keys that do something, each drawn as a key cap.
/// The drawings of the logo to choose from, the chosen one outlined.
class _LogoChoices extends StatelessWidget {
  const _LogoChoices({required this.selected, required this.onSelected});

  final DharaLogoStyle selected;
  final ValueChanged<DharaLogoStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    const corners = BorderRadius.all(Radius.circular(.7 * rem));
    return Wrap(
      spacing: .35 * rem,
      runSpacing: .35 * rem,
      children: [
        for (final style in DharaLogoStyle.values)
          Pressable(
            key: Key('set-logo-${style.name}'),
            onPressed: () => onSelected(style),
            semanticLabel: '${style.label} logo',
            tooltip: style.label,
            selected: style == selected,
            builder: (context, state) => FocusRing(
              visible: state.focused,
              radius: corners,
              child: Container(
                padding: const EdgeInsets.all(.2 * rem),
                decoration: BoxDecoration(
                  borderRadius: corners,
                  border: Border.all(
                    width: 2,
                    color: style == selected
                        ? DharaColors.accent
                        : state.active
                        ? DharaColors.stroke
                        : const Color(0x00000000),
                  ),
                ),
                child: DharaLogo(size: 2.1 * rem, style: style),
              ),
            ),
          ),
      ],
    );
  }
}

class _Keys extends StatelessWidget {
  const _Keys(this.keys);

  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: keys.join(', '),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, key) in keys.indexed) ...[
              if (index > 0) const SizedBox(width: .35 * rem),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: .5 * rem,
                  vertical: .2 * rem,
                ),
                decoration: BoxDecoration(
                  color: DharaColors.surface2,
                  borderRadius: BorderRadius.circular(.35 * rem),
                  border: Border.all(color: DharaColors.strokeStrong),
                ),
                child: Text(
                  key,
                  style: const TextStyle(
                    fontFamily: DharaFonts.ui,
                    fontSize: DharaType.xs,
                    fontWeight: DharaType.semibold,
                    height: 1.3,
                    color: DharaColors.text,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A value with a button to lower it and one to raise it.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.id,
    required this.what,
    required this.text,
    required this.onLess,
    required this.onMore,
    this.valueWidth = 4 * rem,
  });

  /// Used in widget keys: `set-<id>-less`, `set-<id>-value`,
  /// `set-<id>-more`.
  final String id;

  /// What is made smaller or larger, for screen readers.
  final String what;
  final String text;
  final VoidCallback? onLess;
  final VoidCallback? onMore;

  /// Room for the value between the two buttons.
  final double valueWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DharaIconButton(
          key: Key('set-$id-less'),
          icon: DharaIcons.minus,
          label: 'Smaller $what',
          onPressed: onLess,
        ),
        SizedBox(
          width: valueWidth,
          child: Text(
            text,
            key: Key('set-$id-value'),
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(
              fontFamily: DharaFonts.ui,
              fontSize: DharaType.md,
              fontWeight: DharaType.semibold,
              fontFeatures: [FontFeature.tabularFigures()],
              color: DharaColors.text,
            ),
          ),
        ),
        DharaIconButton(
          key: Key('set-$id-more'),
          icon: DharaIcons.add,
          label: 'Larger $what',
          onPressed: onMore,
        ),
      ],
    );
  }
}
