import 'dart:ui';

import 'package:dhara/core/window/window_widgets.dart';
import 'package:dhara/features/sources/source_test_controller.dart';
import 'package:dhara/features/update/ui/update_chip.dart';
import 'package:dhara/shell/activity_chip.dart';
import 'package:dhara/shell/shell_controller.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:dhara/widgets/buttons.dart';
import 'package:dhara/widgets/icons.dart';
import 'package:dhara/widgets/logo.dart';
import 'package:dhara/widgets/pressable.dart';
import 'package:flutter/material.dart';

/// The app's own title bar: Back, the brand, in a production build what
/// the app is doing to the library in the background and whether a newer
/// version of the app exists, the search field in
/// the middle, the state of the servers and, once the system's title bar
/// is gone, the window buttons. Its empty space moves the window.
///
/// It is glass: clear while a page's artwork lies under it, and otherwise
/// blurring what scrolls past beneath.
class TitleBar extends StatelessWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    return SizedBox(
      height: DharaLayout.titleBarHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: WindowDragArea(child: _Ground(clear: shell.artUnderBar)),
          ),
          Positioned.fill(
            child: Row(
              children: [
                const SizedBox(width: DharaSpace.s4),
                if (shell.canGoBack) ...[
                  DharaIconButton(
                    key: const Key('shell-back'),
                    icon: DharaIcons.back,
                    label: 'Back (Alt+Left)',
                    onPressed: shell.back,
                  ),
                  const SizedBox(width: DharaSpace.s2),
                ],
                _Brand(onPressed: () => shell.open(ShellDestination.home)),
                // A development build has its own pages for this.
                if (!shell.devTools) ...[
                  const SizedBox(width: DharaSpace.s4),
                  const ActivityChip(),
                ],
                // There only when a newer version is known.
                const UpdateChip(),
                const Spacer(),
                const _ServerStatus(),
                const SizedBox(width: DharaSpace.s2),
                const WindowButtons(),
              ],
            ),
          ),
          // In the middle of the window, whatever stands left and right.
          const Positioned.fill(child: Center(child: _SearchField())),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: WindowTopResizeEdge(),
          ),
        ],
      ),
    );
  }
}

/// What the bar stands on: nothing over artwork, blurring glass otherwise.
class _Ground extends StatelessWidget {
  const _Ground({required this.clear});

  final bool clear;

  @override
  Widget build(BuildContext context) {
    final pane = AnimatedContainer(
      key: const Key('shell-bar-ground'),
      duration: motion(context, DharaMotion.base),
      decoration: BoxDecoration(
        color: clear ? const Color(0x000C0E18) : DharaColors.glass,
        border: Border(
          bottom: BorderSide(
            color: clear ? const Color(0x00FFFFFF) : DharaColors.stroke,
          ),
        ),
      ),
    );
    if (clear) return pane;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: DharaBlur.glass,
          sigmaY: DharaBlur.glass,
        ),
        child: pane,
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Pressable(
    key: const Key('shell-brand'),
    onPressed: onPressed,
    semanticLabel: 'Dhara home',
    builder: (context, state) => FocusRing(
      visible: state.focused,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DharaLogo(),
          SizedBox(width: .55 * rem),
          Text(
            'Dhara',
            style: TextStyle(
              fontFamily: DharaFonts.display,
              fontSize: 1.05 * rem,
              fontWeight: DharaType.bold,
              letterSpacing: .02 * 1.05 * rem,
              height: 1.2,
              color: DharaColors.text,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The search pill. The results follow what is typed; Ctrl+K or `/`
/// brings the keyboard here from anywhere in the shell.
class _SearchField extends StatefulWidget {
  const _SearchField();

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  ShellController? _shell;
  var _hovered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.read(context);
    if (shell == _shell) return;
    _shell?.searchFocus.removeListener(_onFocus);
    _shell = shell..searchFocus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _shell?.searchFocus.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final shell = _shell!;
    final focused = shell.searchFocus.hasFocus;
    final width = MediaQuery.sizeOf(context).width;
    const style = TextStyle(
      fontFamily: DharaFonts.ui,
      fontSize: DharaType.sm,
      height: 1.3,
      color: DharaColors.text,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: motion(context, DharaMotion.fast),
        width: (width * .36).clamp(12 * rem, 30 * rem),
        height: 1.95 * rem,
        padding: const EdgeInsets.only(left: .75 * rem, right: .5 * rem),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DharaRadii.pill),
          color: focused
              ? const Color(0xD90C0E18)
              : _hovered
              ? DharaColors.surface2
              : DharaColors.surface,
          border: Border.all(
            color: focused
                ? DharaColors.accent
                : _hovered
                ? DharaColors.strokeStrong
                : DharaColors.stroke,
          ),
          boxShadow: focused ? DharaShadows.focusRing : null,
        ),
        child: Row(
          children: [
            Icon(
              DharaIcons.search,
              size: 1.05 * rem,
              color: focused ? DharaColors.text : DharaColors.text2,
            ),
            const SizedBox(width: .6 * rem),
            Expanded(
              child: TextField(
                key: const Key('shell-search'),
                controller: shell.searchText,
                focusNode: shell.searchFocus,
                onChanged: (_) => shell.searchChanged(),
                onSubmitted: (_) => shell.submitSearch(),
                // Ctrl+K selects the text itself. Selecting it whenever
                // the keyboard comes back (it does while Search opens)
                // would let the next key replace what was typed.
                selectAllOnFocus: false,
                autocorrect: false,
                enableSuggestions: false,
                maxLines: 1,
                style: style,
                cursorHeight: DharaType.sm * 1.3,
                decoration: InputDecoration.collapsed(
                  hintText: 'Search films and shows …',
                  hintStyle: style.copyWith(color: DharaColors.text2),
                ),
              ),
            ),
            const SizedBox(width: .5 * rem),
            const _KeyHint('Ctrl K'),
          ],
        ),
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint(this.keys);

  final String keys;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: .4 * rem,
        vertical: .05 * rem,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(.3 * rem),
        border: Border.all(color: DharaColors.stroke),
      ),
      child: Text(
        keys,
        style: const TextStyle(
          fontFamily: DharaFonts.ui,
          fontSize: .68 * rem,
          height: 1.3,
          color: DharaColors.text3,
        ),
      ),
    ),
  );
}

/// How many servers answered when they were last tested. A click opens
/// Server Discovery.
class _ServerStatus extends StatelessWidget {
  const _ServerStatus();

  @override
  Widget build(BuildContext context) {
    final tests = SourcesScope.of(context);
    final shell = ShellScope.read(context);
    final sources = tests.store.sources;
    var online = 0;
    var tested = 0;
    for (final source in sources) {
      final status = tests.statusOf(source.id);
      if (status == SourceStatus.readable ||
          status == SourceStatus.unreadable) {
        online++;
      }
      if (status != SourceStatus.untested && status != SourceStatus.testing) {
        tested++;
      }
    }
    final String strong;
    final String rest;
    final Color dot;
    if (tests.isTesting) {
      strong = '${tests.done}';
      rest = ' / ${tests.total} tested …';
      dot = DharaColors.warn;
    } else if (tested == 0) {
      strong = '${sources.length}';
      rest = sources.length == 1
          ? ' server, not tested'
          : ' servers, not tested';
      dot = DharaColors.text3;
    } else {
      strong = '$online';
      rest = ' / ${sources.length} servers online';
      dot = online > 0 ? DharaColors.good : DharaColors.bad;
    }
    final radius = BorderRadius.circular(DharaRadii.pill);
    return Pressable(
      key: const Key('shell-servers'),
      onPressed: () => shell.open(ShellDestination.discovery),
      tooltip: 'Open Server Discovery',
      builder: (context, state) => FocusRing(
        visible: state.focused,
        radius: radius,
        child: AnimatedContainer(
          duration: motion(context, DharaMotion.fast),
          padding: const EdgeInsets.symmetric(
            horizontal: .65 * rem,
            vertical: .25 * rem,
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: state.hovered ? DharaColors.surface2 : DharaColors.surface,
            border: Border.all(color: DharaColors.stroke),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: .45 * rem,
                height: .45 * rem,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: dot, blurRadius: .5 * rem)],
                ),
              ),
              const SizedBox(width: .45 * rem),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: strong,
                      style: const TextStyle(
                        color: DharaColors.text,
                        fontWeight: DharaType.semibold,
                      ),
                    ),
                    TextSpan(text: rest),
                  ],
                ),
                maxLines: 1,
                style: const TextStyle(
                  fontFamily: DharaFonts.ui,
                  fontSize: DharaType.xs,
                  height: 1.3,
                  color: DharaColors.text2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
