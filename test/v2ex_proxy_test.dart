// Some networks route to V2EX and some do not, so the proxy is optional and
// the app has to be right either way: direct by default, everything through
// the proxy once one is set (including the query string, which Dio only
// appends at send time), and — when a request never gets through — a message
// naming whichever of the two is actually broken.
import 'dart:convert';
import 'dart:io';

import 'package:codora/core/forum_source.dart';
import 'package:codora/core/models.dart';
import 'package:codora/core/proxy.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/features/providers.dart';
import 'package:codora/sources/v2ex_source.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Uri v2ex(String path) => Uri.parse('https://www.v2ex.com$path');

void main() {
  resetBootstrapState();

  group('proxy address', () {
    test('a blank or half-typed address is no proxy at all', () {
      for (final raw in ['', '   ', 'p.example.com', 'ftp://p.example.com']) {
        expect(UrlProxy.parse(raw), isNull, reason: '"$raw" is not usable yet');
      }
    });

    test('a prefix gets the target appended, trailing slash or not', () {
      const target = 'https://www.v2ex.com/api/topics/hot.json';
      for (final prefix in ['https://p.example.com', 'https://p.example.com/']) {
        expect(UrlProxy.parse(prefix)!.applyTo(target),
            'https://p.example.com/$target');
      }
    });

    test('{url} says where the target goes', () {
      final proxy = UrlProxy.parse('https://p.example.com/proxy/{url}')!;
      expect(proxy.applyTo('https://www.v2ex.com/t/1'),
          'https://p.example.com/proxy/https://www.v2ex.com/t/1');
    });

    test('{encoded_url} escapes it, for a proxy that takes a parameter', () {
      final proxy = UrlProxy.parse('https://p.example.com/?to={encoded_url}')!;
      expect(proxy.applyTo('https://www.v2ex.com/?tab=all'),
          'https://p.example.com/?to=https%3A%2F%2Fwww.v2ex.com%2F%3Ftab%3Dall');
    });
  });

  group('images', () {
    final picture = Uri.parse('https://i.imgur.com/abc.png');

    SiteImages imagesWith(AppSettings settings) =>
        containerWith(settings).read(siteImagesProvider(SiteId.v2ex));

    test('go direct when no proxy is set', () {
      expect(V2exSource().images.url(picture), picture);
      expect(imagesWith(const AppSettings()).url(picture), picture);
    });

    test('follow the proxy by default, whichever host they are on', () {
      final images =
          imagesWith(const AppSettings(v2exProxy: 'https://p.example.com'));
      expect(images.url(picture).toString(),
          'https://p.example.com/https://i.imgur.com/abc.png');
      expect(images.url(v2ex('/avatar.png')).toString(),
          'https://p.example.com/https://www.v2ex.com/avatar.png');
    });

    test('go direct when the reader has opted them out', () {
      final images = imagesWith(const AppSettings(
          v2exProxy: 'https://p.example.com', v2exProxyImages: false));
      expect(images.url(picture), picture);
      expect(images.url(v2ex('/avatar.png')), v2ex('/avatar.png'));
    });

    test('opting out does not disturb the feed', () {
      // The switch says nothing about the topic list, so it must not rebuild
      // the source — that would drop the feed into loading and refetch it.
      final c = containerWith(
          const AppSettings(v2exProxy: 'https://p.example.com'));
      final before = c.read(sourceProvider(SiteId.v2ex));
      c.read(settingsProvider.notifier)
          .patch((s) => s.copyWith(v2exProxyImages: false));

      expect(identical(c.read(sourceProvider(SiteId.v2ex)), before), isTrue);
      expect(c.read(siteImagesProvider(SiteId.v2ex)).url(picture), picture);
    });
  });

  group('requests', () {
    late HttpServer server;
    final asked = <String>[];

    setUp(() async {
      asked.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        asked.add(req.uri.toString());
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(const []));
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    String origin() => 'http://127.0.0.1:${server.port}';

    test('an API call arrives at the proxy carrying the real address',
        () async {
      final src = V2exSource(proxy: origin());
      await src.fetchTopics(const Section(id: 'hot', title: '最热'));
      expect(asked.single, '/https://www.v2ex.com/api/topics/hot.json');
    });

    test('the query string travels inside the proxied address', () async {
      final src = V2exSource(proxy: origin());
      try {
        await src.fetchTopic('123');
      } catch (_) {
        // The stub answers with an empty list; only the address matters here.
      }
      expect(asked.single, '/https://www.v2ex.com/api/topics/show.json?id=123');
    });
  });

  group('how the site is being reached', () {
    test('says so on the card, direct or proxied', () {
      expect(V2exSource().access.label, '直连');
      expect(V2exSource(token: 't').access.label, '直连 · Token');
      expect(V2exSource(proxy: 'https://p.example.com').access.label, '经代理');
      expect(V2exSource(proxy: 'https://p.example.com', token: 't').access.label,
          '经代理 · Token');
    });

    test('a direct reader is never told to set one up', () {
      // Nothing about the default source mentions a proxy: plenty of networks
      // route to V2EX perfectly well.
      expect(V2exSource().accessNote, isNot(startsWith('代理')));
      expect(V2exSource().images.rewrite, isNull);
    });
  });

  group('when a request never gets through', () {
    final failure = DioException.connectionTimeout(
      timeout: const Duration(seconds: 15),
      requestOptions: RequestOptions(path: '/api/topics/hot.json'),
    );

    test('with no proxy, it points at the setting that fixes it', () {
      final err = V2exSource().unreachableError(failure);
      expect(err.site, SiteId.v2ex);
      expect(err.recovery, AuthRecovery.settings,
          reason: 'the error offers a way to settings');
      expect(err.message, '连不上 V2EX');
      expect(err.hint, contains('代理地址'));
    });

    test('with a proxy, it blames the proxy rather than V2EX', () {
      final err =
          V2exSource(proxy: 'https://p.example.com').unreachableError(failure);
      expect(err.message, '代理没能连上 V2EX');
      expect(err.hint, contains('确认代理地址'));
      expect(err.hint, isNot(contains('填一个代理')),
          reason: 'there already is one; telling them to add one is noise');
    });

    test('a proxy that refuses the connection surfaces as that', () async {
      // A port nothing is listening on: the request is made for real and
      // never lands, which is what a dead proxy looks like.
      final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close(force: true);

      await expectLater(
        V2exSource(proxy: 'http://127.0.0.1:$port')
            .fetchTopics(const Section(id: 'hot', title: '最热')),
        throwsA(isA<AuthRequiredException>()
            .having((e) => e.message, 'message', '代理没能连上 V2EX')
            .having((e) => e.recovery, 'recovery', AuthRecovery.settings)),
      );
    });
  });
}
