// The app finds out about a newer build from the releases the release
// workflow publishes. What matters is that it offers one only when it really
// is newer, and says nothing wrong when there is none or GitHub cannot be
// reached.
import 'dart:convert';
import 'dart:typed_data';

import 'package:codora/core/updates.dart';
import 'package:codora/features/providers.dart';
import 'package:codora/features/settings_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Answers every request with [status] and [body].
class _Canned implements HttpClientAdapter {
  _Canned(this.status, [this.body = const {}]);
  final int status;
  final Map<String, Object?> body;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Dio answering(int status, [Map<String, Object?> body = const {}]) =>
    Dio()..httpClientAdapter = _Canned(status, body);

void main() {
  resetBootstrapState();

  group('versions', () {
    test('are compared part by part, as numbers', () {
      expect(compareVersions('0.10.0', '0.9.0'), 1);
      expect(compareVersions('1.2.3', '1.2.4'), -1);
      expect(compareVersions('2.0.0', '10.0.0'), -1);
    });

    test('ignore a leading v, a build number and a pre-release tail', () {
      expect(compareVersions('v1.2.0', '1.2.0'), 0);
      expect(compareVersions('1.2.0+7', '1.2.0'), 0);
      expect(compareVersions('v1.3.0-beta', '1.2.9'), 1);
    });

    test('count missing parts as zero', () {
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2.1', '1.2'), 1);
    });
  });

  group('the newest release', () {
    test('is offered when it is newer', () async {
      final release = await newerRelease('0.1.0',
          dio: answering(200, {
            'tag_name': 'v0.2.0',
            'html_url': 'https://github.com/MMortise/Codora/releases/tag/v0.2.0',
            'body': '更新说明',
          }));
      expect(release, isNotNull);
      expect(release!.version, '0.2.0');
      expect(release.url.path, '/MMortise/Codora/releases/tag/v0.2.0');
      expect(release.notes, '更新说明');
    });

    test('is not offered when it is the one running, or older', () async {
      final body = {
        'tag_name': 'v0.1.0',
        'html_url': 'https://github.com/MMortise/Codora/releases/tag/v0.1.0',
      };
      expect(await newerRelease('0.1.0', dio: answering(200, body)), isNull);
      expect(await newerRelease('0.2.0', dio: answering(200, body)), isNull);
    });

    test('is nothing at all before the first release', () async {
      expect(await newerRelease('0.1.0', dio: answering(404)), isNull);
    });

    test('a failure other than that is reported, not taken as up to date',
        () async {
      expect(newerRelease('0.1.0', dio: answering(503)),
          throwsA(isA<DioException>()));
    });
  });

  group('the panel', () {
    Future<void> pumpPanel(WidgetTester tester,
        Future<Release?> Function() answer) async {
      final c = await pumpApp(
        tester,
        const AboutPanel(),
        overrides: [
          appVersionProvider.overrideWith((_) async => '0.1.0'),
          updateProvider.overrideWith((_) => answer()),
        ],
      );
      addTearDown(() => disposeApp(tester, c));
    }

    testWidgets('shows the version running', (tester) async {
      await pumpPanel(tester, () async => null);
      expect(find.text('0.1.0'), findsOneWidget);
      expect(find.text('已是最新版本'), findsOneWidget);
    });

    testWidgets('offers a newer release', (tester) async {
      await pumpPanel(
          tester,
          () async => Release(
              version: '0.2.0',
              url: Uri.parse(
                  'https://github.com/MMortise/Codora/releases/tag/v0.2.0')));
      expect(find.text('新版本 0.2.0'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '前往下载'), findsOneWidget);
    });

    testWidgets('says so when it could not check, and can try again',
        (tester) async {
      var calls = 0;
      await pumpPanel(tester, () async {
        calls++;
        throw StateError('offline');
      });
      expect(find.text('没能检查更新'), findsOneWidget);
      await tester.tap(find.text('再试一次'));
      await tester.pumpAndSettle();
      expect(calls, 2);
    });
  });
}
