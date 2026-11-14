import 'dart:async';

import 'package:dhara/features/indexer/ui/index_screen.dart';
import 'package:dhara/features/metadata/ui/anime_screen.dart';
import 'package:dhara/features/metadata/ui/titles_screen.dart';
import 'package:dhara/features/player/open_url_dialog.dart';
import 'package:dhara/features/sources/ui/server_discovery_screen.dart';
import 'package:dhara/shell/home_placeholder.dart';
import 'package:dhara/shell/nav_rail.dart';
import 'package:dhara/shell/shell_controller.dart';
import 'package:dhara/shell/title_bar.dart';
import 'package:dhara/theme/tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The frame every page of the app sits in: the title bar on top, the
/// navigation rail on the left, and between them the page, which is the
/// only part that changes.
///
/// The player is not a page of the shell: it opens above it and takes the
/// whole window.
///
/// Keys, anywhere in the shell: Ctrl+K or `/` to search, Ctrl+O to play a
/// URL, Alt+Left to go back, Esc to leave a text field or else go back.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// How far a page starts from the left edge: clear of the rail.
  static const pageInsetLeft = NavRail.margin + NavRail.width + .5 * rem;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final _shell = ShellController(pageFor: _pageFor);

  @override
  void dispose() {
    _shell.dispose();
    super.dispose();
  }

  static Widget _pageFor(ShellDestination place, String? query) =>
      switch (place) {
        ShellDestination.home => const HomePlaceholder(),
        ShellDestination.titles => TitlesScreen(initialQuery: query),
        ShellDestination.anime => const AnimeScreen(),
        ShellDestination.library => const IndexScreen(),
        ShellDestination.discovery => const ServerDiscoveryScreen(),
      };

  /// Whether the keyboard is in a text field (the focus of a text field
  /// belongs to a widget inside its `EditableText`).
  bool get _typing {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null &&
        (context.widget is EditableText ||
            context.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final plain =
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed;

    if (keyboard.isControlPressed && key == LogicalKeyboardKey.keyK) {
      _shell.focusSearch();
      return KeyEventResult.handled;
    }
    if (keyboard.isControlPressed && key == LogicalKeyboardKey.keyO) {
      unawaited(showOpenUrlDialog(context));
      return KeyEventResult.handled;
    }
    if (keyboard.isAltPressed && key == LogicalKeyboardKey.arrowLeft) {
      _shell.back();
      return KeyEventResult.handled;
    }
    if (plain && key == LogicalKeyboardKey.slash && !_typing) {
      _shell.focusSearch();
      return KeyEventResult.handled;
    }
    if (plain && key == LogicalKeyboardKey.escape) {
      if (_typing) {
        FocusManager.instance.primaryFocus?.unfocus();
        return KeyEventResult.handled;
      }
      if (_shell.canGoBack) {
        _shell.back();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// The "back" button on the side of a mouse.
  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons & kBackMouseButton != 0) {
      _shell.back();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShellScope(
      controller: _shell,
      // A focus scope of its own: when a field lets go of the keyboard,
      // the focus comes to rest here, not above the shell, where these
      // keys would no longer be heard.
      child: FocusScope(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerDown: _onPointerDown,
          child: Material(
            color: DharaColors.bg,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: DharaLayout.titleBarHeight,
                      left: AppShell.pageInsetLeft,
                    ),
                    // Pages keep their own order of focus; Tab leaves the
                    // title bar and the rail before it enters the page.
                    child: FocusTraversalGroup(
                      child: Navigator(
                        key: _shell.navigatorKey,
                        observers: [_shell.observer],
                        onGenerateInitialRoutes: (navigator, name) => [
                          _shell.routeFor(ShellDestination.home),
                        ],
                        onGenerateRoute: (settings) =>
                            _shell.routeFor(ShellDestination.home),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: FocusTraversalGroup(child: const TitleBar()),
                ),
                const Positioned(
                  left: NavRail.margin,
                  top: DharaLayout.titleBarHeight + .6 * rem,
                  bottom: NavRail.margin,
                  child: NavRail(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
