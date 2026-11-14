import 'package:dhara/core/secrets/secret_store.dart';
import 'package:dhara/features/metadata/tmdb_client.dart';
import 'package:flutter/widgets.dart';

export 'package:dhara/features/metadata/tmdb_client.dart'
    show TmdbKeyCheck, TmdbKeyKind;

/// What [text] is, going by its shape alone, or `null` if it is neither a
/// TMDB token nor a TMDB key. Says nothing about whether TMDB accepts it.
TmdbKeyKind? tmdbKeyKindOf(String text) {
  if (_apiKey.hasMatch(text)) return TmdbKeyKind.apiKey;
  if (text.length >= 80 && text.length <= 1024 && _token.hasMatch(text)) {
    return TmdbKeyKind.accessToken;
  }
  return null;
}

final _apiKey = RegExp(r'^[0-9a-fA-F]{32}$');

/// Three runs of base64url separated by dots, the first one the start of a
/// JSON object.
final _token = RegExp(r'^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$');

/// Why a TMDB key was not saved or removed.
enum TmdbKeyProblem {
  /// What was entered is neither a token nor a key.
  notAKey,

  /// The secure storage refused.
  storage,
}

/// Asks TMDB whether it accepts a key.
typedef TmdbKeyChecker =
    Future<TmdbKeyCheck> Function(String key, TmdbKeyKind kind);

/// The user's TMDB key: whether there is one, saving and removing it, and
/// asking TMDB whether it is accepted. The key itself is held nowhere but
/// in the [SecretStore]; it is never logged, shown again or put into an
/// error message.
class TmdbKeyController extends ChangeNotifier {
  TmdbKeyController(this._store, {TmdbKeyChecker check = checkTmdbKey})
    : _check = check;

  /// The name the key is kept under.
  static const secretName = 'tmdb';

  final SecretStore _store;
  final TmdbKeyChecker _check;
  TmdbKeyKind? _kind;
  TmdbKeyCheck? _lastCheck;
  var _checks = 0;
  var _checking = false;
  var _loaded = false;
  var _unreadable = false;

  /// [load] has finished.
  bool get isLoaded => _loaded;

  /// What is saved, or `null` if no key is.
  TmdbKeyKind? get kind => _kind;

  bool get hasKey => _kind != null;

  /// The secure storage could not be read; whether a key is saved is not
  /// known.
  bool get unreadable => _unreadable;

  /// Whether a saved key is still there after the app restarts.
  bool get keptAfterRestart => _store.keepsSecrets;

  /// TMDB is being asked about the key right now.
  bool get isChecking => _checking;

  /// What TMDB said about the saved key when it was last asked in this
  /// run; `null` if it has not been asked.
  TmdbKeyCheck? get lastCheck => _lastCheck;

  /// Finds out whether a key is saved. Call once at start-up. Never
  /// throws.
  Future<void> load() async {
    await key();
    _loaded = true;
    _notify();
  }

  /// The saved key, to sign a request with, or `null` if there is none or
  /// it cannot be read. Never throws.
  Future<String?> key() async {
    final before = (_kind, _unreadable);
    String? saved;
    try {
      saved = await _store.read(secretName);
      _kind = saved == null ? null : tmdbKeyKindOf(saved);
      _unreadable = false;
    } on SecretStoreException {
      _kind = null;
      _unreadable = true;
    }
    // Removed or changed behind the app's back, in Credential Manager.
    if (before != (_kind, _unreadable)) {
      _forgetCheck();
      if (_loaded) _notify();
    }
    return _kind == null ? null : saved;
  }

  /// Saves what the user entered as the key. Returns what went wrong, or
  /// `null` if it is saved.
  Future<TmdbKeyProblem?> save(String entered) async {
    final text = entered.trim();
    final kind = tmdbKeyKindOf(text);
    if (kind == null) return TmdbKeyProblem.notAKey;
    try {
      await _store.write(secretName, text);
    } on SecretStoreException {
      return TmdbKeyProblem.storage;
    }
    _kind = kind;
    _unreadable = false;
    _forgetCheck();
    _notify();
    return null;
  }

  /// Removes the saved key. Returns what went wrong, or `null`.
  Future<TmdbKeyProblem?> remove() async {
    try {
      await _store.delete(secretName);
    } on SecretStoreException {
      return TmdbKeyProblem.storage;
    }
    _kind = null;
    _unreadable = false;
    _forgetCheck();
    _notify();
    return null;
  }

  /// Asks TMDB whether it accepts the saved key; [lastCheck] has the
  /// answer afterwards. Returns `null` if no key is saved. Never throws.
  Future<TmdbKeyCheck?> test() async {
    final saved = await key();
    final kind = _kind;
    if (saved == null || kind == null) return null;
    final number = ++_checks;
    _checking = true;
    _notify();
    TmdbKeyCheck result;
    try {
      result = await _check(saved, kind);
    } on Exception {
      result = TmdbKeyCheck.unreachable;
    }
    // The key was changed or removed meanwhile, or asked about again: this
    // answer is about something else.
    if (number != _checks) return result;
    _checking = false;
    _lastCheck = result;
    _notify();
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  var _disposed = false;

  /// What TMDB said was about another key.
  void _forgetCheck() {
    _checks++;
    _checking = false;
    _lastCheck = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// Makes the [TmdbKeyController] available to the widget tree.
class TmdbKeyScope extends InheritedNotifier<TmdbKeyController> {
  const TmdbKeyScope({
    super.key,
    required TmdbKeyController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller; the calling widget rebuilds whenever it changes.
  static TmdbKeyController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TmdbKeyScope>();
    assert(scope != null, 'No TmdbKeyScope above this widget');
    return scope!.notifier!;
  }

  /// The controller, without rebuilding on changes (for event handlers).
  static TmdbKeyController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<TmdbKeyScope>();
    assert(scope != null, 'No TmdbKeyScope above this widget');
    return scope!.notifier!;
  }
}
