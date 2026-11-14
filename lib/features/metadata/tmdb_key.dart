import 'package:dhara/core/secrets/secret_store.dart';
import 'package:flutter/foundation.dart';

/// The two things a TMDB account offers to sign requests with.
enum TmdbKeyKind {
  /// "API Read Access Token": sent as a header, so it never sits in an
  /// address. The one to prefer.
  accessToken('API Read Access Token'),

  /// "API Key" (v3): 32 hex digits, sent as part of the address.
  apiKey('API key');

  const TmdbKeyKind(this.label);

  final String label;
}

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

/// The user's TMDB key: whether there is one, and saving and removing it.
/// The key itself is held nowhere but in the [SecretStore]; it is never
/// logged, shown again or put into an error message.
class TmdbKeyController extends ChangeNotifier {
  TmdbKeyController(this._store);

  /// The name the key is kept under.
  static const secretName = 'tmdb';

  final SecretStore _store;
  TmdbKeyKind? _kind;
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

  /// Finds out whether a key is saved. Call once at start-up. Never
  /// throws.
  Future<void> load() async {
    await key();
    _loaded = true;
    notifyListeners();
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
    if (_loaded && before != (_kind, _unreadable)) notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
    return null;
  }
}
