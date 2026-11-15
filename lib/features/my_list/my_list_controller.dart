import 'dart:async';

import 'package:dhara/core/db/library_db.dart';
import 'package:dhara/core/db/library_isolate.dart';
import 'package:dhara/features/home/home_store.dart';
import 'package:dhara/features/my_list/my_list_store.dart';
import 'package:flutter/widgets.dart';

/// My List, held in memory so that any card or button can ask at once
/// whether a title is on it; changes are written to the library database
/// behind.
///
/// Without a working library the list lasts for this run only.
class MyListController extends ChangeNotifier {
  MyListController({required LibraryWorker library}) : _library = library;

  final LibraryWorker _library;

  // The one added last comes first.
  var _ids = <int>[];
  var _disposed = false;

  /// The ids of the titles on the list, the one added last first.
  List<int> get ids => List.unmodifiable(_ids);

  bool contains(int title) => _ids.contains(title);

  /// Reads the saved list. Call once at start-up. Never throws.
  Future<void> load() async {
    try {
      _ids = await _library.run(_readIds, null);
    } on LibraryWorkException {
      // This run starts with an empty list.
    }
    _notify();
  }

  /// Puts [title] on the list, or takes it off if it is on it. Returns
  /// whether it is on the list now.
  bool toggle(int title) {
    final on = !_ids.contains(title);
    if (on) {
      _ids.insert(0, title);
    } else {
      _ids.remove(title);
    }
    _notify();
    // If writing fails, the list is still right until the app closes.
    unawaited(
      _library.run(_write, (title, on)).then((_) {}, onError: (Object _) {}),
    );
    return on;
  }

  /// The titles on the list as cards, the one added last first. A title
  /// whose videos are gone from the sources in [sourceIds] (the enabled
  /// ones) is still listed, with no videos. Never throws.
  Future<List<TitleCard>> cards(List<String> sourceIds) async {
    try {
      return await _library.run(_readCards, (ids, sourceIds));
    } on LibraryWorkException {
      return const [];
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// Makes the [MyListController] available to the widget tree.
class MyListScope extends InheritedNotifier<MyListController> {
  const MyListScope({
    super.key,
    required MyListController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller; the calling widget rebuilds whenever the list changes.
  static MyListController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MyListScope>();
    assert(scope != null, 'No MyListScope above this widget');
    return scope!.notifier!;
  }

  /// The controller, without rebuilding on changes (for event handlers).
  static MyListController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<MyListScope>();
    assert(scope != null, 'No MyListScope above this widget');
    return scope!.notifier!;
  }
}

// What follows runs in the library isolate.

List<int> _readIds(LibraryDb db, Object? _) => MyListStore(db).ids();

List<TitleCard> _readCards(LibraryDb db, (List<int>, List<String>) request) {
  final (ids, sourceIds) = request;
  return HomeStore(
    db,
    sourceIds: sourceIds,
  ).cards(ids, whateverItsState: true, evenWithoutVideos: true);
}

void _write(LibraryDb db, (int, bool) change) {
  final (title, on) = change;
  final list = MyListStore(db);
  if (on) {
    list.add(title);
  } else {
    list.remove(title);
  }
}
