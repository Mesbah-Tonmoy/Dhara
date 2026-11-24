import 'dart:convert';

import 'package:dhara/core/net/safe_http_client.dart';
import 'package:dhara/features/update/update_notice.dart';

/// The address a production build asks for updates, out of what it was
/// given when it was built (`DHARA_UPDATE_URL`); `null` if that is nothing,
/// or nothing it may ask: only an https address without a user name or
/// password will do.
Uri? updateUrlFrom(String value) {
  final url = Uri.tryParse(value.trim());
  if (url == null ||
      url.scheme != 'https' ||
      url.host.isEmpty ||
      url.userInfo.isNotEmpty ||
      url.hasFragment) {
    return null;
  }
  return url;
}

/// Why asking for updates gave no notice.
enum UpdateAskProblem {
  /// The place did not answer: no connection, or it is down.
  unreachable,

  /// It answered, but not with an update notice: the file is gone or not
  /// shared any more, or the place asks for something first.
  notThere,

  /// What came is not signed with the key this copy was built with.
  notSigned,

  /// A signed notice this version cannot use.
  notUsable,
}

/// What [UpdateChecker.ask] came back with: a notice, or why there is none.
class UpdateAnswer {
  const UpdateAnswer.notice(UpdateNotice this.notice, String this.text)
    : problem = null;
  const UpdateAnswer.problem(UpdateAskProblem this.problem)
    : notice = null,
      text = null;

  /// The newest version the place knows of, which need not be newer than
  /// this copy.
  final UpdateNotice? notice;

  /// The notice as it came, signature and all: to keep, and to check
  /// again when it is read back.
  final String? text;

  final UpdateAskProblem? problem;
}

/// Asks whether a newer version of the app exists.
///
/// It asks the one address it was made with and no other: a redirect to
/// another host is refused. The request carries nothing about the user,
/// the library or the version that is installed (no cookie, no header of
/// its own, no parameter), and what comes back is an update notice only
/// if its signature fits (see [readUpdateNotice]).
class UpdateChecker {
  UpdateChecker(
    this.url, {
    required bool Function(List<int> message, List<int> signature) signed,
    SafeHttpClient? client,
  }) : _signed = signed,
       _client =
           client ?? SafeHttpClient(isAllowedHost: (host) => host == url.host);

  final Uri url;
  final bool Function(List<int> message, List<int> signature) _signed;
  final SafeHttpClient _client;

  /// Asks the place. Never throws.
  Future<UpdateAnswer> ask() async {
    final SafeHttpResponse response;
    try {
      response = await _client.get(
        url,
        maxBytes: maxUpdateNoticeBytes,
        timeout: const Duration(seconds: 20),
      );
    } on SafeHttpException catch (error) {
      return UpdateAnswer.problem(switch (error.failure) {
        SafeHttpFailure.timeout ||
        SafeHttpFailure.network => UpdateAskProblem.unreachable,
        SafeHttpFailure.tooLarge ||
        SafeHttpFailure.blockedUrl ||
        SafeHttpFailure.blockedRedirect ||
        SafeHttpFailure.tooManyRedirects => UpdateAskProblem.notThere,
      });
    }
    // Only a plain "200 OK" is the file.
    if (response.statusCode != 200) {
      return const UpdateAnswer.problem(UpdateAskProblem.notThere);
    }
    return read(response.bodyBytes);
  }

  /// Reads a notice that came from [url]: one just fetched, or one that
  /// was kept from an earlier asking, which is checked like a new one.
  UpdateAnswer read(List<int> bytes) {
    final read = readUpdateNotice(bytes, signed: _signed, askedAt: url);
    final notice = read.notice;
    if (notice != null) {
      return UpdateAnswer.notice(notice, utf8.decode(bytes));
    }
    return UpdateAnswer.problem(switch (read.problem!) {
      UpdateNoticeProblem.notANotice => UpdateAskProblem.notThere,
      UpdateNoticeProblem.notSigned => UpdateAskProblem.notSigned,
      UpdateNoticeProblem.notUsable => UpdateAskProblem.notUsable,
    });
  }

  /// Ends an asking under way, which then reports the place as
  /// unreachable.
  void close() => _client.close();
}
