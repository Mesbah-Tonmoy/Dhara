import 'package:shared_preferences/shared_preferences.dart';

/// Minimal typed key-value storage for user settings.
///
/// Reads are synchronous (values are cached in memory); writes are persisted
/// in the background. A value of the wrong type reads as `null`, so a
/// hand-edited or corrupted settings file falls back to defaults instead of
/// crashing the app.
abstract interface class KeyValueStore {
  int? getInt(String key);
  double? getDouble(String key);
  String? getString(String key);

  Future<void> setInt(String key, int value);
  Future<void> setDouble(String key, double value);
  Future<void> setString(String key, String value);

  /// Forgets the value of [key], whatever its type.
  Future<void> remove(String key);
}

/// In-memory store for tests and as a fallback when the settings file cannot
/// be opened.
class MemoryKeyValueStore implements KeyValueStore {
  MemoryKeyValueStore([Map<String, Object>? initial]) : values = {...?initial};

  final Map<String, Object> values;

  @override
  int? getInt(String key) {
    final value = values[key];
    return value is int ? value : null;
  }

  @override
  double? getDouble(String key) {
    final value = values[key];
    return value is num ? value.toDouble() : null;
  }

  @override
  String? getString(String key) {
    final value = values[key];
    return value is String ? value : null;
  }

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> setInt(String key, int value) async => values[key] = value;

  @override
  Future<void> setDouble(String key, double value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

/// Settings stored by `shared_preferences`: on Windows a small JSON file in
/// the per-user application data folder. No secrets are kept here.
class SharedPrefsStore implements KeyValueStore {
  SharedPrefsStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<SharedPrefsStore> open() async {
    return SharedPrefsStore._(await SharedPreferences.getInstance());
  }

  @override
  int? getInt(String key) {
    final value = _prefs.get(key);
    return value is int ? value : null;
  }

  @override
  double? getDouble(String key) {
    final value = _prefs.get(key);
    return value is num ? value.toDouble() : null;
  }

  @override
  String? getString(String key) {
    final value = _prefs.get(key);
    return value is String ? value : null;
  }

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  @override
  Future<void> setDouble(String key, double value) =>
      _prefs.setDouble(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}
