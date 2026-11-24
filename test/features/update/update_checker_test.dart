import 'dart:convert';
import 'dart:io';

import 'package:dhara/core/app_info.dart';
import 'package:dhara/features/update/update_checker.dart';
import 'package:dhara/features/update/update_notice.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/local_server.dart';
import '../../support/update_notices.dart';

void main() {
  group('the address a build was given', () {
    test('is taken if it is a plain https address', () {
      expect(
        updateUrlFrom(' https://files.example/get?id=abc_1-2&confirm=t\n'),
        Uri.parse('https://files.example/get?id=abc_1-2&confirm=t'),
      );
    });

    test('is not taken if it is anything else', () {
      for (final value in const [
        '',
        'dhara-update.json',
        'http://files.example/dhara-update.json',
        'ftp://files.example/dhara-update.json',
        'file:///C:/dhara-update.json',
        'https:///dhara-update.json',
        'https://user:pass@files.example/dhara-update.json',
        'https://files.example/dhara-update.json#part',
        'https://files.example:port/dhara-update.json',
      ]) {
        expect(updateUrlFrom(value), isNull, reason: value);
      }
    });
  });

  group('asking', () {
    late LocalServer server;
    var fits = true;

    setUp(() async {
      server = await LocalServer.start();
      fits = true;
    });
    tearDown(() => server.close());

    UpdateChecker checker([String path = '/notice']) => UpdateChecker(
      server.url(path),
      signed: (message, signature) => fits,
      client: server.client(),
    );

    /// A notice whose installer lies where the notice is asked for.
    String notice({String version = '1.2.0', String? installer}) =>
        updateNoticeText(
          version: version,
          installer:
              installer ?? 'https://127.0.0.1:${server.url('/').port}/setup',
        );

    test('gives the notice that lies there, and the text it came as', () async {
      final text = notice();
      server.serve('/notice', text, contentType: 'application/json');

      final answer = await checker().ask();
      expect(answer.problem, isNull);
      expect(answer.notice!.version, const AppVersion(1, 2, 0));
      expect(answer.text, text);
    });

    test('says nothing about the user, the library or this copy', () async {
      server.serve('/notice', notice(), contentType: 'application/json');
      await checker().ask();

      final request = server.requests.single;
      expect(request.method, 'GET');
      expect(request.uri.toString(), '/notice');
      final sent = <String, String>{};
      request.headers.forEach((name, values) => sent[name] = values.join(','));
      expect(sent.keys.toSet(), {
        'user-agent',
        'accept-encoding',
        'host',
      }, reason: 'no cookie, and no header of the app\'s own');
      expect(sent['user-agent'], 'Dhara');
      expect(sent.values.join(' '), isNot(contains(dharaVersion)));
      expect(request.cookies, isEmpty);
    });

    test('a file that is not there is not there', () async {
      expect((await checker('/gone').ask()).problem, UpdateAskProblem.notThere);
      server.serve('/moved', notice(), status: HttpStatus.partialContent);
      expect(
        (await checker('/moved').ask()).problem,
        UpdateAskProblem.notThere,
      );
    });

    test('a page in place of the file is not a notice', () async {
      server.serve('/notice', '<html><body>Sign in to continue</body></html>');
      expect((await checker().ask()).problem, UpdateAskProblem.notThere);
    });

    test('an answer larger than a notice may be is not read', () async {
      server.serve('/notice', 'x' * (maxUpdateNoticeBytes + 1));
      expect((await checker().ask()).problem, UpdateAskProblem.notThere);
    });

    test('a redirect to another host is not followed', () async {
      final other = await LocalServer.start();
      addTearDown(other.close);
      other.serve('/notice', notice(), contentType: 'application/json');
      // The same server by another name is another host.
      server.redirect(
        '/notice',
        'http://localhost:${other.url('/').port}/notice',
      );

      expect((await checker().ask()).problem, UpdateAskProblem.notThere);
      expect(other.requests, isEmpty);
    });

    test('a place that does not answer is unreachable', () async {
      final asking = checker();
      await server.close();
      expect((await asking.ask()).problem, UpdateAskProblem.unreachable);
    });

    test('a notice whose signature does not fit is not signed', () async {
      server.serve('/notice', notice(), contentType: 'application/json');
      fits = false;
      final answer = await checker().ask();
      expect(answer.notice, isNull);
      expect(answer.problem, UpdateAskProblem.notSigned);
    });

    test('a signed notice that points elsewhere is not usable', () async {
      server.serve(
        '/notice',
        notice(installer: 'https://elsewhere.example/setup'),
        contentType: 'application/json',
      );
      expect((await checker().ask()).problem, UpdateAskProblem.notUsable);
    });

    test('a notice that was kept is checked like one that was fetched', () {
      final asking = checker();
      final kept = utf8.encode(notice(version: '2.0.0'));
      expect(asking.read(kept).notice!.version, const AppVersion(2, 0, 0));
      fits = false;
      expect(asking.read(kept).problem, UpdateAskProblem.notSigned);
      expect(server.requests, isEmpty);
    });
  });
}
