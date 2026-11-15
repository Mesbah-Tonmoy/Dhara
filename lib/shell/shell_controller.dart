import 'dart:async';

import 'package:dhara/widgets/icons.dart';
import 'package:flutter/material.dart';

/// The places the navigation rail leads to.
///
/// The list grows as Phase 6 builds the screens of the prototype; until
/// then the working screens of the earlier phases stand in.
enum ShellDestination {
  home('Home', DharaIcons.home),

  /// Search, which is also how Movies and Series are browsed.
  search('Search', DharaIcons.search),
  anime('Anime', DharaIcons.anime),
  myList('My List', DharaIcons.myList),
  history('History', DharaIcons.history),

  /// How many titles there are, the TMDB key, matching and Needs review.
  /// Opened from Settings (and from Home's notices).
  titles('Titles and matching', DharaIcons.matching, onRail: false),

  /// Opened from Settings (and from Home's notices).
  library('Library index', DharaIcons.library, onRail: false),
  discovery('Server Discovery', DharaIcons.servers, low: true),
  settings('Settings', DharaIcons.settings, low: true);

  const ShellDestination(
    this.label,
    this.icon, {
    this.low = false,
    this.onRail = true,
  });

  final String label;
  final IconData icon;

  /// Kept at the foot of the rail, with the tools rather than the content.
  final bool low;

  /// Has an icon on the rail. The others are tools reached from Settings;
  /// while one of them is open, the rail lights Settings.
  final bool onRail;
}

/// Where the app is, and how it moves: the pages inside the shell (title
/// bar and rail stay, the page between them changes).
///
/// The pages live in a [Navigator] of their own, [navigatorKey]. Its first
/// page is always Home; a place of the rail is opened on top of Home,
/// replacing the place that was open, and pages opened from there (a
/// title, a list of copies) go on top of that. So Back always leads toward
/// Home, and at most one place of the rail is alive at a time.
class ShellController extends ChangeNotifier {
  ShellController({required this.pageFor, this.onSearch, this.onSearchStart});

  /// Builds the page of a place of the rail. For [ShellDestination.titles],
  /// [query] is what to search for at once.
  final Widget Function(ShellDestination destination, String? query) pageFor;

  /// Told what the search field holds whenever that changes.
  final ValueChanged<String>? onSearch;

  /// Called when typing opens Search from another page: a search that
  /// starts elsewhere is over everything, not over what was browsed last.
  final VoidCallback? onSearchStart;

  final navigatorKey = GlobalKey<NavigatorState>();

  /// The search field of the title bar.
  final searchFocus = FocusNode(debugLabel: 'title-bar-search');
  final searchText = TextEditingController();

  late final NavigatorObserver observer = _StackObserver(this);

  final _stack = <Route<dynamic>>[];

  /// The place of the rail the page on screen belongs to.
  ShellDestination get current {
    for (final route in _stack.reversed) {
      final place = _placeOf(route);
      if (place != null) return place;
    }
    return ShellDestination.home;
  }

  /// False on Home, where there is nothing to go back to.
  bool get canGoBack => _stack.length > 1;

  final _artUnderBar = <Route<dynamic>>{};

  /// The page on screen has artwork running under the title bar right now,
  /// so the bar is clear glass; otherwise it has a ground of its own.
  bool get artUnderBar =>
      _stack.isNotEmpty && _artUnderBar.contains(_stack.last);

  /// A page says whether its artwork is under the title bar (it is not
  /// once the page has scrolled). [route] is the page's own route.
  void setArtUnderBar(Route<dynamic> route, bool under) {
    if (_disposed) return;
    final changed = under
        ? _artUnderBar.add(route)
        : _artUnderBar.remove(route);
    if (changed) _changed();
  }

  /// Opens [destination], unless it is what is on screen already.
  void open(ShellDestination destination, {String? query}) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    if (destination == ShellDestination.home) {
      navigator.popUntil((route) => route.isFirst);
      return;
    }
    final onTop = _stack.isNotEmpty && _placeOf(_stack.last) == destination;
    if (onTop && query == null) return;
    unawaited(
      navigator.pushAndRemoveUntil(
        routeFor(destination, query: query),
        (route) => route.isFirst,
      ),
    );
  }

  /// Opens [destination] on top of the page on screen, so that Back leads
  /// to that page again (Settings opens its tools like this).
  void openOver(ShellDestination destination) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    if (_stack.isNotEmpty && _placeOf(_stack.last) == destination) return;
    unawaited(navigator.push(routeFor(destination)));
  }

  /// The route that shows [destination].
  Route<void> routeFor(ShellDestination destination, {String? query}) =>
      MaterialPageRoute<void>(
        settings: RouteSettings(name: destination.name),
        builder: (_) => pageFor(destination, query),
      );

  /// One page back, if there is one.
  void back() => unawaited(navigatorKey.currentState?.maybePop());

  /// Puts the keyboard into the search field, with its text selected.
  void focusSearch() {
    searchFocus.requestFocus();
    searchText.selection = TextSelection(
      baseOffset: 0,
      extentOffset: searchText.text.length,
    );
  }

  /// The search field was typed into: the search follows, and its page
  /// opens if another one is on screen.
  void searchChanged() {
    final text = searchText.text;
    final starts = text.trim().isNotEmpty && current != ShellDestination.search;
    if (starts) onSearchStart?.call();
    onSearch?.call(text);
    if (starts) {
      open(ShellDestination.search);
      _keepTyping();
    }
  }

  /// Opens Search and puts the keyboard into the search field.
  void openSearch() {
    open(ShellDestination.search);
    _keepTyping();
  }

  /// A page that opens takes the keyboard; this gives it back to the
  /// search field, with the caret where it was, so that typing goes on.
  void _keepTyping() {
    final selection = searchText.selection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      searchFocus.requestFocus();
      // A field that gains the keyboard may select all its text; the next
      // key would then replace what was typed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed || !selection.isValid) return;
        final length = searchText.text.length;
        searchText.selection = TextSelection(
          baseOffset: selection.baseOffset.clamp(0, length),
          extentOffset: selection.extentOffset.clamp(0, length),
        );
      });
    });
  }

  /// Enter in the search field: shows the results and lets go of the
  /// keyboard, so that the arrow keys walk the results.
  void submitSearch() {
    if (searchText.text.trim().isEmpty) return;
    searchChanged();
    searchFocus.unfocus();
  }

  static ShellDestination? _placeOf(Route<dynamic> route) {
    final name = route.settings.name;
    for (final place in ShellDestination.values) {
      if (place.name == name) return place;
    }
    return null;
  }

  void _changed() {
    // Routes change while the navigator builds; listeners rebuild after.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }

  var _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    searchFocus.dispose();
    searchText.dispose();
    super.dispose();
  }
}

class _StackObserver extends NavigatorObserver {
  _StackObserver(this._shell);

  final ShellController _shell;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _shell._stack.add(route);
    _shell._changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _shell._stack.remove(route);
    _shell._artUnderBar.remove(route);
    _shell._changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _shell._stack.remove(route);
    _shell._artUnderBar.remove(route);
    _shell._changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final at = oldRoute == null ? -1 : _shell._stack.indexOf(oldRoute);
    if (at >= 0 && newRoute != null) {
      _shell._stack[at] = newRoute;
    } else if (newRoute != null) {
      _shell._stack.add(newRoute);
    }
    _shell._changed();
  }
}

/// Makes the [ShellController] available to the pages inside the shell.
class ShellScope extends InheritedNotifier<ShellController> {
  const ShellScope({
    super.key,
    required ShellController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller; the calling widget rebuilds when the page changes.
  static ShellController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'No ShellScope above this widget');
    return scope!.notifier!;
  }

  /// The controller, without rebuilding on changes (for event handlers).
  static ShellController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'No ShellScope above this widget');
    return scope!.notifier!;
  }

  /// As [read], or `null` for a page shown outside the shell.
  static ShellController? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellScope>()?.notifier;
}
