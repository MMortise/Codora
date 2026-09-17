// Live integration checks against the real sites.
// Run with:
//   flutter test --dart-define=LIVE=true \
//     --dart-define=LINUXDO_COOKIE="cf_clearance=...; ..." test/sources_live_test.dart
import 'dart:io';

import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/sources/juejin_source.dart';
import 'package:codora/sources/linuxdo_source.dart';
import 'package:codora/sources/v2ex_source.dart';
import 'package:flutter_test/flutter_test.dart';

const live = bool.fromEnvironment('LIVE');
const linuxdoCookie = String.fromEnvironment('LINUXDO_COOKIE');

void main() {
  group('V2EX', () {
    final src = V2exSource();
    test('hot feed, topic, replies', () async {
      final sections = await src.sections();
      final hot = sections.firstWhere((s) => s.id == 'hot');
      final feed = await src.fetchTopics(hot);
      expect(feed.items, isNotEmpty);
      final first = feed.items.first;
      expect(first.title, isNotEmpty);
      expect(first.author?.name, isNotEmpty);
      final detail = await src.fetchTopic(first.id);
      expect(detail.title, first.title);
      final withReplies = feed.items.firstWhere((t) => (t.replyCount ?? 0) > 0);
      final replies = await src.fetchReplies(withReplies.id);
      expect(replies.items, isNotEmpty);
      expect(replies.items.first.floor, 1);
      expect(replies.items.first.author?.name, isNotEmpty);
    });
    test('全部 tab is first and scrapes the site front page', () async {
      final sections = await src.sections();
      expect(sections.first.id, 'all');
      expect(sections.first.title, '全部');

      final feed = await src.fetchTopics(sections.first);
      expect(feed.items.length, greaterThan(30));
      expect(feed.nextCursor, isNull, reason: '全部 is a single page');

      final first = feed.items.first;
      expect(first.id, matches(RegExp(r'^\d+$')));
      expect(first.title, isNotEmpty);
      expect(first.url, startsWith('https://www.v2ex.com/t/'));
      expect(first.author?.name, isNotEmpty);
      expect(first.author?.avatarUrl, startsWith('https://'));
      // The page ships full-size avatars; the list only needs small ones.
      expect(feed.items.map((t) => t.author?.avatarUrl ?? '').where(
          (u) => u.contains('_xlarge.')), isEmpty);
      expect(feed.items.where((t) => t.author?.avatarUrl == null), isEmpty);
      expect(first.sectionLabel, isNotEmpty);
      expect(first.lastActiveAt, isNotNull);
      expect(first.lastActiveAt!.isBefore(DateTime.now().add(const Duration(minutes: 5))),
          isTrue);

      // Ordered by latest reply, so the newest activity leads.
      final withReplies = feed.items.where((t) => (t.replyCount ?? 0) > 0);
      expect(withReplies, isNotEmpty);

      // Ids are unique, i.e. the page was parsed row by row.
      expect(feed.items.map((t) => t.id).toSet().length, feed.items.length);
    });

    test('node feed without token', () async {
      final feed = await src.fetchTopics(const Section(id: 'node:python', title: 'Python'));
      expect(feed.items, isNotEmpty);
      expect(feed.items.first.sectionLabel, 'Python');
    });
    test('url parsing', () {
      expect(src.topicIdFromUrl(Uri.parse('https://www.v2ex.com/t/1242215#reply3')), '1242215');
      expect(src.topicIdFromUrl(Uri.parse('https://example.com/t/1')), isNull);
    });
  }, skip: live ? false : 'set --dart-define=LIVE=true');

  group('Juejin', () {
    final src = JuejinSource();
    test('sections include categories', () async {
      final sections = await src.sections();
      expect(sections.map((s) => s.id), containsAll(['recommend', 'latest', 'hot']));
      expect(sections.where((s) => s.group == '分类'), isNotEmpty);
    });
    test('recommend feed pages and detail renders markdown', () async {
      final page1 = await src.fetchTopics(const Section(id: 'recommend', title: '推荐'));
      expect(page1.items, isNotEmpty);
      expect(page1.nextCursor, isNotNull);
      final page2 = await src.fetchTopics(const Section(id: 'recommend', title: '推荐'),
          cursor: page1.nextCursor);
      expect(page2.items, isNotEmpty);
      final detail = await src.fetchTopic(page1.items.first.id);
      expect(detail.content, isNotEmpty);
      expect(detail.format, BodyFormat.markdown,
          reason: 'Juejin ships markdown, so it should not be pre-converted');
      expect(detail.content, isNot(startsWith('---')),
          reason: 'front matter is stripped');
      expect(detail.author?.name, isNotEmpty);
    });
    test('hot rank and category feed', () async {
      final hot = await src.fetchTopics(const Section(id: 'hot', title: '热榜'));
      expect(hot.items, isNotEmpty);
      final cate = await src.fetchTopics(
          const Section(id: 'cate:6809637769959178254', title: '后端'));
      expect(cate.items, isNotEmpty);
    });
    test('comments with nested replies', () async {
      final replies = await src.fetchReplies('7637856870833635343');
      expect(replies.items, isNotEmpty);
      expect(replies.total, greaterThan(100));
      expect(replies.nextCursor, isNotNull);
      expect(replies.items.any((r) => r.children.isNotEmpty), isTrue);
      expect(replies.items.first.author?.name, isNotEmpty);
    });
  }, skip: live ? false : 'set --dart-define=LIVE=true');

  // linux.do fetches through a real WebView (Cloudflare binds its clearance
  // to the browser that earned it), which `flutter test` cannot host. Only the
  // pure logic is covered here; the network path is exercised in the app.
  group('Linux.do', () {
    final src = LinuxDoSource(
        cookie: 'cf_clearance=x; _t=y', userAgent: kDesktopUserAgent);

    test('reports access from the stored cookie', () {
      expect(
          LinuxDoSource(cookie: '', userAgent: kDesktopUserAgent).access.level,
          AccessLevel.blocked);
      expect(
          LinuxDoSource(cookie: 'cf_clearance=x', userAgent: kDesktopUserAgent)
              .access
              .level,
          AccessLevel.limited);
      expect(src.access.level, AccessLevel.full);
    });

    test('asks for verification before any request', () {
      final bare = LinuxDoSource(cookie: '', userAgent: kDesktopUserAgent);
      expect(
        () => bare.fetchTopics(const Section(id: 'latest', title: '最新')),
        throwsA(isA<AuthRequiredException>().having(
            (e) => e.recovery, 'recovery', AuthRecovery.browser)),
      );
    });

    test('loads images through the browser only once verified', () {
      expect(LinuxDoSource(cookie: '', userAgent: kDesktopUserAgent).imageLoader,
          isNull);
      expect(src.imageLoader, isNotNull);
      expect(src.imageHeaders, isNull);
    });

    test('only the forum domain goes through the browser', () {
      final loader = src.imageLoader!;

      // Posts and emoji live on the open CDN. Routing them through the
      // linux.do page would make them cross-origin requests and they would
      // fail, so the loader must decline them.
      for (final open in [
        'https://cdn3.ldstatic.com/original/4X/a/b/c/deadbeef.png',
        'https://cdn.ldstatic.com/images/emoji/twemoji/rofl.png?v=15',
        'https://example.com/whatever.png',
      ]) {
        expect(loader(Uri.parse(open)), isNull,
            reason: '$open is reachable without the browser');
      }

      // The forum's own domain is behind the challenge and does need it.
      // Checked through the predicate, since calling the loader here would
      // spin up a real WebView that unit tests cannot host.
      expect(src.needsBrowser(Uri.parse('https://linux.do/user_avatar/x/96/1.png')),
          isTrue);
      expect(src.needsBrowser(Uri.parse('https://cdn3.ldstatic.com/a.png')), isFalse);
      expect(src.needsBrowser(Uri.parse('https://cdn.ldstatic.com/e.png')), isFalse);
    });

    test('the image CDN really is reachable without the browser', () async {
      // The routing above is only correct if a plain client can read these.
      // If this ever fails, post images must go back through the browser.
      final client = HttpClient();
      addTearDown(client.close);
      for (final url in [
        'https://cdn.ldstatic.com/images/emoji/twemoji/rofl.png?v=15',
        'https://cdn3.ldstatic.com/original/4X/a/8/2/'
            'a82b64f686a4f7c682d5d93b1e6077585c84085e.png',
      ]) {
        final req = await client.getUrl(Uri.parse(url));
        req.headers.set('User-Agent', kDesktopUserAgent);
        final res = await req.close();
        expect(res.statusCode, 200, reason: url);
        expect(res.headers.contentType?.primaryType, 'image', reason: url);
        expect(res.headers.value('cf-mitigated'), isNull,
            reason: '$url must not be challenged');
        await res.drain<void>();
      }
    }, skip: live ? false : 'needs network');

    test('url parsing', () {
      expect(src.topicIdFromUrl(Uri.parse('https://linux.do/t/topic/2910060/3')),
          '2910060');
      expect(src.topicIdFromUrl(Uri.parse('https://linux.do/t/2910060')), '2910060');
      expect(src.topicIdFromUrl(Uri.parse('https://example.com/t/1')), isNull);
    });
  });

  group('site descriptors', () {
    test('every site fills in what the shell renders', () {
      final sources = [
        V2exSource(),
        LinuxDoSource(cookie: '', userAgent: kDesktopUserAgent),
        JuejinSource(),
      ];
      expect(sources.map((s) => s.id).toSet(), SiteId.values.toSet());
      for (final s in sources) {
        expect(s.name, isNotEmpty, reason: '\${s.id} name');
        expect(s.glyph, isNotEmpty, reason: '\${s.id} glyph');
        expect(s.glyph.length, lessThanOrEqualTo(2), reason: '\${s.id} glyph');
        expect(s.iconAsset, startsWith('assets/icons/'), reason: '\${s.id} icon');
        expect(s.iconAsset, endsWith('.png'), reason: '\${s.id} icon');
        expect(s.accessNote, isNotEmpty, reason: '\${s.id} accessNote');
        expect(s.access.label, isNotEmpty, reason: '\${s.id} access label');
        expect(s.homeUrl.scheme, 'https', reason: '\${s.id} homeUrl');
      }
    });

    test('anonymous sites are readable without setup', () {
      expect(V2exSource().access.level, AccessLevel.open);
      expect(JuejinSource().access.level, AccessLevel.open);
    });
  });
}
