import 'dart:async';
import 'dart:convert';

import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/features/update/update_checker.dart';
import 'package:dhara/features/update/update_notice.dart';
import 'package:flutter/widgets.dart';

/// Knows whether a newer version of the app exists.
///
/// Only a production build that was given an address to ask and the key to
/// check the answer with has one. It asks once a day at most by itself,
/// and whenever the user asks; it fetches the update notice and nothing
/// else. Nothing is downloaded or started here.
class UpdateController extends ChangeNotifier {
  UpdateController({
    required UpdateChecker checker,
    required KeyValueStore settings,
    required this.current,
    DateTime Function() clock = DateTime.now,
  }) : _checker = checker,
       _settings = settings,
       _clock = clock;

  /// Where the time of the last asking is kept (milliseconds).
  static const askedAtKey = 'update.askedAt';

  /// Where the notice of a newer version is kept, as it came, so that the
  /// app knows of it again when it starts, without asking. It is checked
  /// again when it is read back.
  static const noticeKey = 'update.notice';

  /// By itself the app asks no more often than this.
  static const askEvery = Duration(days: 1);

  /// The version this copy is.
  final AppVersion current;

  final UpdateChecker _checker;
  final KeyValueStore _settings;
  final DateTime Function() _clock;

  UpdateNotice? _available;
  UpdateAskProblem? _problem;

  /// When this run last asked: counts even if the settings could not
  /// keep it.
  DateTime? _asked;
  Future<void>? _asking;
  Timer? _first;
  Timer? _looking;
  var _disposed = false;

  /// The newer version there is, if the app knows of one.
  UpdateNotice? get available => _available;

  /// The place is being asked right now.
  bool get isAsking => _asking != null;

  /// Why the last asking of this run gave no notice; `null` if it gave
  /// one, or if none was made yet.
  UpdateAskProblem? get problem => _problem;

  /// When the place was last asked; `null` if it never was.
  DateTime? get askedAt =>
      _asked ??
      switch (_settings.getInt(askedAtKey)) {
        final int at => DateTime.fromMillisecondsSinceEpoch(at),
        null => null,
      };

  /// Takes up what an earlier run found out, asks once the app has
  /// settled if the last asking is a day old, and looks again every
  /// [look] whether it is, for as long as the app runs.
  void start({
    Duration first = const Duration(seconds: 30),
    Duration look = const Duration(hours: 1),
  }) {
    _restore();
    _first = Timer(first, () => unawaited(askIfDue()));
    _looking = Timer.periodic(look, (_) => unawaited(askIfDue()));
  }

  /// Asks, unless the place was asked within the last day.
  Future<void> askIfDue() async {
    final at = askedAt;
    final now = _clock();
    // A time in the future is a clock that was set back: it says nothing.
    if (at != null && !at.isAfter(now) && now.difference(at) < askEvery) {
      return;
    }
    await askNow();
  }

  /// Asks now: the user wants to know. Never throws.
  Future<void> askNow() {
    final running = _asking;
    if (running != null) return running;
    final asking = _ask();
    _asking = asking;
    _notify();
    return asking;
  }

  @override
  void dispose() {
    _disposed = true;
    _first?.cancel();
    _looking?.cancel();
    _checker.close();
    super.dispose();
  }

  Future<void> _ask() async {
    try {
      // Noted first: an asking that goes wrong is not made again and
      // again.
      final at = _asked = _clock();
      await _keep(
        () => _settings.setInt(askedAtKey, at.millisecondsSinceEpoch),
      );
      final answer = await _checker.ask();
      if (_disposed) return;
      _problem = answer.problem;
      final notice = answer.notice;
      if (notice != null) {
        if (notice.version.isNewerThan(current)) {
          _available = notice;
          await _keep(() => _settings.setString(noticeKey, answer.text!));
        } else {
          _available = null;
          await _keep(() => _settings.remove(noticeKey));
        }
      }
      // After an asking that failed, what was known before still holds.
    } finally {
      _asking = null;
      _notify();
    }
  }

  /// Reads the notice an earlier run kept. It goes through the same check
  /// as one that was just fetched, and is dropped unless it still names a
  /// version newer than this copy (it does not after the update).
  void _restore() {
    final kept = _settings.getString(noticeKey);
    if (kept == null) return;
    final notice = _checker.read(utf8.encode(kept)).notice;
    if (notice != null && notice.version.isNewerThan(current)) {
      _available = notice;
      _notify();
    } else {
      unawaited(_keep(() => _settings.remove(noticeKey)));
    }
  }

  /// Writes to the settings. If that fails, what was found out still
  /// holds for this run.
  static Future<void> _keep(Future<void> Function() write) async {
    try {
      await write();
    } on Exception {
      // Not kept.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// Makes the [UpdateController] available to the widget tree.
class UpdateScope extends InheritedNotifier<UpdateController> {
  const UpdateScope({
    super.key,
    required UpdateController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, if there is one above (only a production build that
  /// can ask for updates has one); the calling widget rebuilds whenever
  /// it changes.
  static UpdateController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UpdateScope>()?.notifier;

  /// The same, without rebuilding on changes (for event handlers).
  static UpdateController? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<UpdateScope>()?.notifier;
}
