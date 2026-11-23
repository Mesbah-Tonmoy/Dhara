/// A secret could not be read, kept or removed. [message] is plain English
/// and never contains the secret.
class SecretStoreException implements Exception {
  const SecretStoreException(this.message);

  final String message;

  @override
  String toString() => 'SecretStoreException: $message';
}

/// Where the app keeps the few secrets it has (the TMDB key): the secure
/// storage of the operating system, never the settings file, the database
/// or a log.
///
/// Every method may throw a [SecretStoreException].
abstract interface class SecretStore {
  /// Whether what is written here is still there after the app restarts.
  bool get keepsSecrets;

  /// The secret kept under [name], or `null` if there is none.
  Future<String?> read(String name);

  /// Keeps [value] under [name], replacing what was there.
  Future<void> write(String name, String value);

  /// Removes the secret kept under [name]; nothing happens if there is
  /// none.
  Future<void> delete(String name);
}

/// The longest secret a [SecretStore] takes, in UTF-8 bytes. Windows
/// Credential Manager holds 2560; a TMDB token is a few hundred.
const maxSecretBytes = 2048;

/// Whether [name] can name a secret: lower-case letters, digits, "-", "_"
/// and ".", at most 64 of them.
bool isSecretName(String name) => _secretName.hasMatch(name);

final _secretName = RegExp(r'^[a-z0-9._-]{1,64}$');

/// Holds the one secret a build was made with, and nothing else: for the
/// TMDB key of a production build, which is part of the program. It cannot
/// be replaced or removed, and it is written nowhere by the app.
class BuiltInSecretStore implements SecretStore {
  const BuiltInSecretStore(this._name, this._value);

  final String _name;
  final String _value;

  static const _fixed = SecretStoreException(
    'This build carries its key; it cannot be changed.',
  );

  @override
  bool get keepsSecrets => true;

  @override
  Future<String?> read(String name) async => name == _name ? _value : null;

  @override
  Future<void> write(String name, String value) async => throw _fixed;

  @override
  Future<void> delete(String name) async => throw _fixed;
}

/// Keeps secrets in memory, for this run only: for tests, and for systems
/// where the app has no secure storage yet.
class MemorySecretStore implements SecretStore {
  final _secrets = <String, String>{};

  @override
  bool get keepsSecrets => false;

  @override
  Future<String?> read(String name) async => _secrets[name];

  @override
  Future<void> write(String name, String value) async {
    if (!isSecretName(name)) {
      throw const SecretStoreException('That is not a name for a secret.');
    }
    _secrets[name] = value;
  }

  @override
  Future<void> delete(String name) async => _secrets.remove(name);
}
