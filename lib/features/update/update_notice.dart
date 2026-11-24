import 'dart:convert';

/// A version of the app: three numbers, as in `1.2.0`.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  /// The version [text] names; `null` unless it is three numbers with
  /// dots between them and nothing else.
  static AppVersion? parse(String text) {
    final match = RegExp(r'^(\d{1,5})\.(\d{1,5})\.(\d{1,5})$').firstMatch(text);
    if (match == null) return null;
    return AppVersion(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// What a signed update notice says: which version is the newest, and
/// which file is its installer.
class UpdateNotice {
  const UpdateNotice({
    required this.version,
    required this.installer,
    required this.size,
    required this.sha256,
    this.notes = '',
  });

  final AppVersion version;

  /// Where the installer is fetched from: an https address on the host
  /// the notice itself came from.
  final Uri installer;

  /// How long the installer is, in bytes, and its SHA-256 in lower-case
  /// hexadecimal. A file that is not exactly this is not the installer.
  final int size;
  final String sha256;

  /// What is new, in the words of whoever made the release: plain text,
  /// to be shown as text.
  final String notes;
}

/// Why a notice was not taken.
enum UpdateNoticeProblem {
  /// It is not an update notice at all: a page, another file, cut off.
  notANotice,

  /// It has the shape of a notice, but its signature does not fit the key
  /// this app was built with.
  notSigned,

  /// It is signed, but says something this version cannot use: a kind of
  /// notice it does not know, or an installer that is not where it may be.
  notUsable,
}

/// What [readUpdateNotice] made of the bytes it was given.
class UpdateNoticeRead {
  const UpdateNoticeRead.taken(UpdateNotice this.notice) : problem = null;
  const UpdateNoticeRead.refused(UpdateNoticeProblem this.problem)
    : notice = null;

  final UpdateNotice? notice;
  final UpdateNoticeProblem? problem;
}

/// The most an update notice may be, in bytes.
const maxUpdateNoticeBytes = 64 * 1024;

/// The most an installer may be, whatever a notice says.
const maxInstallerBytes = 1024 * 1024 * 1024;

/// The most that is kept of a notice's notes, in characters.
const maxUpdateNotesLength = 4000;

/// Reads an update notice: what was fetched from [askedAt], the one
/// address this build asks.
///
/// A notice is untrusted input. It is believed only if [signed] says that
/// its signature fits (`UpdateKey.signed`): the signature is checked over
/// the bytes as they came, before a single one of them is read as
/// content, and what they then say is still taken apart strictly. The
/// installer's address is only taken if it is an https address on the host
/// that was asked.
///
/// The form (`tool/sign-update.ps1` writes it):
///
///     {"dhara_update": 1, "signed": "<base64>", "signature": "<base64>"}
///
/// where `signed` holds, as UTF-8, the JSON
///
///     {"version": "1.2.0", "installer": "https://…", "size": 50651234,
///      "sha256": "<64 hex digits>", "notes": "…"}
///
/// Never throws for anything the bytes hold.
UpdateNoticeRead readUpdateNotice(
  List<int> bytes, {
  required bool Function(List<int> message, List<int> signature) signed,
  required Uri askedAt,
}) {
  const notANotice = UpdateNoticeRead.refused(UpdateNoticeProblem.notANotice);
  const notUsable = UpdateNoticeRead.refused(UpdateNoticeProblem.notUsable);

  if (bytes.isEmpty || bytes.length > maxUpdateNoticeBytes) return notANotice;
  final outer = _jsonObject(bytes);
  if (outer == null) return notANotice;
  final kind = outer['dhara_update'];
  final signedText = outer['signed'];
  final signatureText = outer['signature'];
  if (kind is! int || signedText is! String || signatureText is! String) {
    return notANotice;
  }
  final List<int> message;
  final List<int> signature;
  try {
    message = base64.decode(signedText);
    signature = base64.decode(signatureText);
  } on FormatException {
    return notANotice;
  }
  if (message.isEmpty) return notANotice;

  if (!signed(message, signature)) {
    return const UpdateNoticeRead.refused(UpdateNoticeProblem.notSigned);
  }

  // From here on the bytes are the ones the holder of the key signed.
  // They are still only taken if they are what this version expects.
  if (kind != 1) return notUsable;
  final told = _jsonObject(message);
  if (told == null) return notUsable;
  final versionText = told['version'];
  final installerText = told['installer'];
  final size = told['size'];
  final sha256 = told['sha256'];
  final notes = told['notes'];
  if (versionText is! String ||
      installerText is! String ||
      size is! int ||
      sha256 is! String ||
      (notes != null && notes is! String)) {
    return notUsable;
  }
  final version = AppVersion.parse(versionText);
  final installer = _installerAddress(installerText, askedAt);
  if (version == null ||
      installer == null ||
      size < 1 ||
      size > maxInstallerBytes ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
    return notUsable;
  }
  return UpdateNoticeRead.taken(
    UpdateNotice(
      version: version,
      installer: installer,
      size: size,
      sha256: sha256,
      notes: _plainText(notes as String? ?? ''),
    ),
  );
}

/// The JSON object [bytes] hold as UTF-8; `null` if they hold anything
/// else.
Map<String, Object?>? _jsonObject(List<int> bytes) {
  try {
    final value = jsonDecode(utf8.decode(bytes));
    return value is Map<String, Object?> ? value : null;
  } on FormatException {
    return null;
  }
}

/// The address of an installer out of what a notice says, if the app may
/// fetch from it: https, on the host and port that were asked for the
/// notice, without a user name or a fragment.
Uri? _installerAddress(String text, Uri askedAt) {
  if (text.length > 2000) return null;
  final url = Uri.tryParse(text);
  if (url == null ||
      url.scheme != 'https' ||
      url.host.isEmpty ||
      url.host != askedAt.host ||
      url.port != askedAt.port ||
      url.userInfo.isNotEmpty ||
      url.hasFragment) {
    return null;
  }
  return url;
}

/// [text] as plain text of a sensible length: without control characters
/// other than the line break.
String _plainText(String text) {
  final cleaned = text
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'[\u0000-\u0009\u000B-\u001F\u007F-\u009F]'), ' ')
      .trim();
  return cleaned.length <= maxUpdateNotesLength
      ? cleaned
      : cleaned.substring(0, maxUpdateNotesLength);
}
