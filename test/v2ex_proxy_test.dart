// Some networks route to V2EX and some do not, so the proxy is optional and
// the app has to be right either way: direct by default, everything through
// the proxy once one is set (including the query string, which Dio only
// appends at send time), and — when a request never gets through — a message
// naming whichever of the two is actually broken.
import 'dart:convert';
import 'dart:io';

import 'package:codora/core/forum_source.dart';
import 'package:codora/core/models.dart';
import 'package:codora/core/http.dart';
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

  group('reading the address', () {
    test('a bare host and port is a tunnel, the way every tool means it', () {
      // What Clash, curl -x and HTTP_PROXY all take.
      expect(SiteProxy.parse('172.16.12.90:27006'),
          const ProxyTunnel('172.16.12.90:27006'));
      expect(SiteProxy.parse('http://127.0.0.1:7890'),
          const ProxyTunnel('127.0.0.1:7890'));
      expect(SiteProxy.parse('  127.0.0.1:7890  '),
          const ProxyTunnel('127.0.0.1:7890'));
    });

    test('a placeholder makes it a rewriter instead', () {
      expect(SiteProxy.parse('https://p.example.com/{url}'),
          isA<ProxyRewrite>());
      expect(SiteProxy.parse('https://p.example.com/?to={encoded_url}'),
          isA<ProxyRewrite>());
    });

    test('an address that cannot be used is no proxy at all', () {
      for (final raw in [
        '',
        '   ',
        'p.example.com', // no port: nothing to tunnel to
        'https://p.example.com/', // a rewriter has to say where the target goes
        'socks5://127.0.0.1:1080', // would need a different client entirely
      ]) {
        expect(SiteProxy.parse(raw), isNull, reason: '"$raw" is not usable');
      }
    });

    test('a tunnel really carries the request', () async {
      // A proxy is asked for the target by absolute URI rather than by path,
      // which is what tells this apart from a rewriter: the address is in the
      // request line, not folded into it.
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => proxy.close(force: true));
      final asked = <String>[];
      proxy.listen((req) async {
        asked.add(req.uri.toString());
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(const []));
        await req.response.close();
      });

      final dio = buildDio(
        baseUrl: 'http://www.v2ex.com',
        proxy: SiteProxy.parse('127.0.0.1:${proxy.port}'),
      );
      await dio.get<dynamic>('/api/topics/hot.json');

      expect(asked.single, 'http://www.v2ex.com/api/topics/hot.json');
    });

    test('a rewriter gets the target appended where it asked', () {
      const target = 'https://www.v2ex.com/api/topics/hot.json';
      expect(
          (SiteProxy.parse('https://p.example.com/{url}')! as ProxyRewrite)
              .applyTo(target),
          'https://p.example.com/$target');
      expect(
          (SiteProxy.parse('https://p.example.com/?to={encoded_url}')!
                  as ProxyRewrite)
              .applyTo('https://www.v2ex.com/?tab=all'),
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

    test('a rewriter changes their address, whichever host they are on', () {
      final images = imagesWith(
          const AppSettings(v2exProxy: 'https://p.example.com/{url}'));
      expect(images.url(picture).toString(),
          'https://p.example.com/https://i.imgur.com/abc.png');
      expect(images.url(v2ex('/avatar.png')).toString(),
          'https://p.example.com/https://www.v2ex.com/avatar.png');
    });

    test('a tunnel fetches them instead of rewriting', () {
      // Image.network has its own HTTP client and would ignore the tunnel, so
      // the bytes have to come through the source's own client.
      final images =
          imagesWith(const AppSettings(v2exProxy: '127.0.0.1:7890'));
      expect(images.rewrite, isNull);
      expect(images.loader, isNotNull);
      expect(images.url(picture), picture);
    });

    test('go direct when the reader has opted them out', () {
      for (final address in ['https://p.example.com/{url}', '127.0.0.1:7890']) {
        final images = imagesWith(
            AppSettings(v2exProxy: address, v2exProxyImages: false));
        expect(images.url(picture), picture);
        expect(images.loader, isNull, reason: '$address must not fetch them');
      }
    });

    test('opting out does not disturb the feed', () {
      // The switch says nothing about the topic list, so it must not rebuild
      // the source — that would drop the feed into loading and refetch it.
      final c = containerWith(
          const AppSettings(v2exProxy: 'https://p.example.com/{url}'));
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

    /// A rewriting proxy pointed at the stub: the target goes in the path.
    String rewriter() => 'http://127.0.0.1:${server.port}/{url}';

    test('an API call arrives at the proxy carrying the real address',
        () async {
      final src = V2exSource(proxy: rewriter());
      await src.fetchTopics(const Section(id: 'hot', title: '最热'));
      expect(asked.single, '/https://www.v2ex.com/api/topics/hot.json');
    });

    test('the query string travels inside the proxied address', () async {
      final src = V2exSource(proxy: rewriter());
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
      expect(V2exSource(proxy: '127.0.0.1:7890').access.label, '经代理');
      expect(V2exSource(proxy: '127.0.0.1:7890', token: 't').access.label,
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
          V2exSource(proxy: '127.0.0.1:7890').unreachableError(failure);
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
