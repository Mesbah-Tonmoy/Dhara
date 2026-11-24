import 'dart:io';

import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/update/update_notice.dart';
import 'package:dhara/features/update/update_signature.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// An installer that was fetched and found to be the very file a signed
/// update notice names: as long, and with that SHA-256.
///
/// Only [InstallerFetcher] makes one, after that check, so whatever takes
/// a [CheckedInstaller] cannot be handed a file that was not checked.
class CheckedInstaller {
  const CheckedInstaller._(this.file, this.version);

  /// For tests of what takes a checked installer.
  @visibleForTesting
  const CheckedInstaller.forTest(this.file, this.version);

  final File file;
  final AppVersion version;
}

/// Why an installer was not fetched.
enum InstallerProblem {
  /// The place it lies at did not answer, or stopped answering.
  unreachable,

  /// It answered, but not with a file.
  notThere,

  /// What came is not the file the notice names: longer, shorter, or with
  /// another SHA-256. It was removed.
  notTheInstaller,

  /// It could not be saved on this PC.
  notSaved,
}

/// What [InstallerFetcher.fetch] did.
class InstallerFetched {
  const InstallerFetched.checked(CheckedInstaller this.installer)
    : problem = null;
  const InstallerFetched.problem(InstallerProblem this.problem)
    : installer = null;

  final CheckedInstaller? installer;
  final InstallerProblem? problem;
}

/// Fetches the installer a signed update notice names, and checks it.
///
/// It fetches from the host the notice was asked from and no other (a
/// redirect elsewhere is refused), without a cookie or a header of its
/// own, and takes no byte more than the notice says the file is long. The
/// file is then read back from the disk: unless its length and its SHA-256
/// are exactly the ones of the notice, it is removed and nothing comes of
/// it. Its name is made here from the version's three numbers; nothing a
/// server says goes into a path.
class InstallerFetcher {
  InstallerFetcher({
    required this.folder,
    required this.host,
    SafeHttpClient Function()? newClient,
  }) : _newClient =
           newClient ??
           (() => SafeHttpClient(isAllowedHost: (asked) => asked == host));

  /// The folder of the app's own that the installer is kept in until it
  /// is started, and that holds nothing else.
  final Directory folder;

  /// The host the update notice was asked from.
  final String host;

  final SafeHttpClient Function() _newClient;
  SafeHttpClient? _client;

  /// What a file of this class is called: the installer of one version,
  /// whole or still being fetched.
  static final _ours = RegExp(r'^Dhara-Setup-\d+\.\d+\.\d+\.exe(\.part)?$');

  /// Fetches the installer of [notice] and checks it. [onProgress] hears
  /// how many of its bytes have come; [onChecking] is called when they all
  /// have and the file is being read back. Never throws.
  Future<InstallerFetched> fetch(
    UpdateNotice notice, {
    void Function(int received)? onProgress,
    void Function()? onChecking,
  }) async {
    const notTheInstaller = InstallerFetched.problem(
      InstallerProblem.notTheInstaller,
    );
    if (notice.installer.host != host) {
      return const InstallerFetched.problem(InstallerProblem.notThere);
    }
    final separator = Platform.pathSeparator;
    final file = File(
      '${folder.path}${separator}Dhara-Setup-${notice.version}.exe',
    );
    final part = File('${file.path}.part');
    final client = _client = _newClient();
    InstallerFetched result;
    try {
      // What an earlier fetch left is not what is started.
      await clear();
      await folder.create(recursive: true);
      final response = await client.download(
        notice.installer,
        part,
        // Not a byte more than the file is long.
        maxBytes: notice.size,
        onProgress: (received, total) => onProgress?.call(received),
      );
      if (response.statusCode != HttpStatus.ok ||
          // A page that asks to confirm or to sign in, not the file.
          (response.header(HttpHeaders.contentTypeHeader) ?? '')
              .toLowerCase()
              .startsWith('text/')) {
        result = const InstallerFetched.problem(InstallerProblem.notThere);
      } else {
        onChecking?.call();
        if (await part.length() != notice.size ||
            await _sha256Of(part) != notice.sha256) {
          result = notTheInstaller;
        } else {
          await part.rename(file.path);
          return InstallerFetched.checked(
            CheckedInstaller._(file, notice.version),
          );
        }
      }
    } on SafeHttpException catch (error) {
      result = switch (error.failure) {
        // The place sends more than the notice says the file is long.
        SafeHttpFailure.tooLarge => notTheInstaller,
        SafeHttpFailure.timeout || SafeHttpFailure.network =>
          const InstallerFetched.problem(InstallerProblem.unreachable),
        SafeHttpFailure.blockedUrl ||
        SafeHttpFailure.blockedRedirect ||
        SafeHttpFailure.tooManyRedirects => const InstallerFetched.problem(
          InstallerProblem.notThere,
        ),
      };
    } on FileSystemException {
      result = const InstallerFetched.problem(InstallerProblem.notSaved);
    } on CngException {
      // Windows could not work out the digest: the file stays unchecked,
      // so it is not the installer.
      result = notTheInstaller;
    } finally {
      client.close();
      if (identical(_client, client)) _client = null;
    }
    // Nothing that was not checked is left lying.
    await _remove(part);
    await _remove(file);
    return result;
  }

  /// Removes what earlier fetches left in [folder]: installers and parts
  /// of them, and nothing else that may lie there.
  Future<void> clear() async {
    try {
      if (!await folder.exists()) return;
      await for (final entry in folder.list(followLinks: false)) {
        final name = entry.path.split(Platform.pathSeparator).last;
        if (entry is File && _ours.hasMatch(name)) {
          await _remove(entry);
        }
      }
    } on FileSystemException {
      // What cannot be removed now is removed before the next fetch.
    }
  }

  /// Ends a fetch under way, which then reports the place as unreachable.
  void cancel() => _client?.close();

  static Future<void> _remove(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A file that is still open: the next fetch writes over it.
    }
  }

  /// The SHA-256 of what [file] holds on the disk, in lower-case hex.
  static Future<String> _sha256Of(File file) async {
    final digest = Sha256();
    try {
      await for (final piece in file.openRead()) {
        digest.add(piece);
      }
      return hexOf(digest.finish());
    } finally {
      digest.close();
    }
  }
}
