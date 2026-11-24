import 'dart:async';
import 'dart:convert';

import 'package:dhara/core/settings/key_value_store.dart';
import 'package:dhara/features/update/installer_fetcher.dart';
import 'package:dhara/features/update/installer_launcher.dart';
import 'package:dhara/features/update/update_checker.dart';
import 'package:dhara/features/update/update_notice.dart';
import 'package:flutter/widgets.dart';

/// What is being done with the installer of a newer version.
enum UpdateStep {
  /// It is being fetched.
  fetching,

  /// It is all there and is being held against the update notice.
  checking,

  /// It is the file the notice names, and is being started.
  starting,
}

/// Knows whether a newer version of the app exists, and fetches, checks
/// and starts its installer when the user says so.
///
/// Only a production build that was given an address to ask and the key to
/// check the answer with has one. By itself it only asks, once a day at
/// most, and what it fetches then is the update notice and nothing else.
/// An installer is fetched when [install] is called, which only a click
/// of the user's does, and it is started only once it was found to be the
/// file the signed notice names.
class UpdateController extends ChangeNotifier {
  UpdateController({
    required UpdateChecker checker,
    required KeyValueStore settings,
    required this.current,
    InstallerFetcher? installers,
    InstallerLauncher? launcher,
    DateTime Function() clock = DateTime.now,
  }) : _checker = checker,
       _settings = settings,
       _installers = installers,
       _launcher = launcher,
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

  /// Fetches installers; without it (the app has no folder to keep one
  /// in) the app can say that there is a newer version and no more.
  final InstallerFetcher? _installers;

  /// Starts an installer that was checked; without it none is started.
  final InstallerLauncher? _launcher;
  final DateTime Function() _clock;

  UpdateNotice? _available;
  UpdateAskProblem? _problem;

  /// When this run last asked: counts even if the settings could not
  /// keep it.
  DateTime? _asked;
  Future<void>? _asking;
  Future<CheckedInstaller?>? _fetching;
  Future<bool>? _installing;
  var _started = false;
  UpdateStep? _step;
  var _received = 0;
  var _stopped = false;
  InstallerProblem? _installerProblem;
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

  /// Whether this copy can fetch the installer of a newer version.
  bool get canFetchInstaller => _installers != null;

  /// Whether this copy can fetch that installer and start it.
  bool get canInstall => _installers != null && _launcher != null;

  /// An installer is being fetched, checked or started right now.
  bool get isInstalling => _installing != null || _fetching != null;

  /// The installer of the newer version was started in this run: it is
  /// open, and the app is to close.
  bool get installerStarted => _started;

  /// What is being done with the installer right now; `null` when
  /// nothing is.
  UpdateStep? get step => _step;

  /// How many bytes of the installer have come, of
  /// `available.size`.
  int get bytesFetched => _received;

  /// Why the last try gave no installer, or did not start it; `null` if
  /// it went well, if it was stopped by the user, or if there was none
  /// yet.
  InstallerProblem? get installerProblem => _installerProblem;

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
    // An installer an earlier run fetched has done its part, or never
    // will: none is kept from one run to the next.
    unawaited(_installers?.clear());
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

  /// Fetches the installer of the newer version and checks it against
  /// the notice: the user asked for it. Gives the installer if it is the
  /// file the notice names, else `null` ([installerProblem] says why, or
  /// nothing if [stopFetching] ended it). Never throws.
  Future<CheckedInstaller?> fetchInstaller() {
    final running = _fetching;
    if (running != null) return running;
    final fetching = _fetch();
    _fetching = fetching;
    _notify();
    return fetching;
  }

  /// Fetches the installer of the newer version, checks it against the
  /// notice and starts it: the user clicked for it. Returns whether the
  /// installer was started; if not, [installerProblem] says why (or
  /// nothing, if [stopFetching] ended it). Never throws.
  ///
  /// The installer runs on by itself; the caller closes the app.
  Future<bool> install() {
    final running = _installing;
    if (running != null) return running;
    final installing = _install();
    _installing = installing;
    return installing;
  }

  /// Ends a fetch under way: the user does not want it after all.
  void stopFetching() {
    if (_fetching == null) return;
    _stopped = true;
    _installers?.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    _first?.cancel();
    _looking?.cancel();
    _checker.close();
    _installers?.cancel();
    super.dispose();
  }

  Future<bool> _install() async {
    try {
      final launcher = _launcher;
      if (launcher == null) return false;
      final installer = await fetchInstaller();
      // Only what the fetcher checked gets this far.
      if (installer == null || _disposed) return false;
      _step = UpdateStep.starting;
      _notify();
      final started = await launcher.start(installer);
      if (started) {
        _started = true;
      } else {
        _installerProblem = InstallerProblem.notStarted;
        // It is not kept for a later try: that one fetches and checks
        // anew.
        await _installers?.clear();
      }
      return started;
    } finally {
      _step = null;
      _installing = null;
      _notify();
    }
  }

  Future<CheckedInstaller?> _fetch() async {
    final notice = _available;
    final installers = _installers;
    try {
      if (notice == null || installers == null) return null;
      _stopped = false;
      _installerProblem = null;
      _received = 0;
      _step = UpdateStep.fetching;
      final lastTold = Stopwatch()..start();
      final fetched = await installers.fetch(
        notice,
        onProgress: (received) {
          _received = received;
          // A fast connection reports hundreds of times a second.
          if (lastTold.elapsedMilliseconds >= 100) {
            lastTold.reset();
            _notify();
          }
        },
        onChecking: () {
          _received = notice.size;
          _step = UpdateStep.checking;
          _notify();
        },
      );
      _installerProblem = _stopped ? null : fetched.problem;
      return fetched.installer;
    } finally {
      _step = null;
      _fetching = null;
      _notify();
    }
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
