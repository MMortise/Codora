// Lists and threads are saved as they arrive. A list opens from its saved copy
// and is replaced when the site answers; a thread falls back to its copy when
// the site cannot be reached. A copy made for one reader is never shown to
// another, and a copy on screen always says it is one.
import 'dart:convert';
import 'dart:typed_data';

import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/core/snapshot.dart';
import 'package:codora/features/providers.dart';
import 'package:codora/features/topic_detail.dart';
import 'package:codora/features/topic_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A site that can be switched off, and says what it served.
class _Site extends FakeSource {
  _Site() : super(null);

  bool down = false;
  bool signInNeeded = false;
  String label = '新';
  int fetches = 0;

  Never _fail() {
    if (signInNeeded) {
      throw AuthRequiredException(SiteId.v2ex, '要先登录', AuthRecovery.settings);
    }
    throw Exception('连不上 V2EX');
  }

  @override
  Future<List<Section>> sections() async =>
      const [Section(id: 'all', title: '全部')];

  @override
  Future<PageResult<TopicSummary>> fetchTopics(Section s,
      {String? cursor}) async {
    fetches++;
    if (down || signInNeeded) _fail();
    return PageResult(items: [
      for (var i = 0; i < 3; i++)
        TopicSummary(
          site: SiteId.v2ex,
          id: '$i',
          title: '$label帖 $i',
          url: 'https://www.v2ex.com/t/$i',
          author: const Author(name: 'neo', avatarUrl: 'https://a/neo.png'),
          sectionLabel: '程序员',
          replyCount: 4,
          lastActiveAt: DateTime(2026, 9, 1, 8),
        ),
    ], nextCursor: '1');
  }

  @override
  Future<TopicDetail> fetchTopic(String id) async {
    if (down || signInNeeded) _fail();
    return TopicDetail(
      site: SiteId.v2ex,
      id: id,
      title: '$label的帖子',
      url: 'https://www.v2ex.com/t/$id',
      content: '<p>$label正文</p>',
      replyCount: 2,
      liked: true,
      canLike: true,
    );
  }

  @override
  Future<PageResult<Reply>> fetchReplies(String id, {String? cursor}) async {
    if (down || signInNeeded) _fail();
    return PageResult(items: [
      Reply(
        id: 'r1',
        content: '<p>$label回复</p>',
        floor: 1,
        quote: const ReplyQuote(author: 'neo', floor: 0, excerpt: '引用'),
        children: const [Reply(id: 'c1', content: '<p>楼中楼</p>')],
      ),
    ], total: 2);
  }
}

const key = FeedKey(SiteId.v2ex, 'all');
const ref = TopicRef(SiteId.v2ex, '0');

void main() {
  resetBootstrapState();

  late Map<Uri, Uint8List> files;
  late _Site site;
  setUp(() {
    files = {};
    Snapshots.instance = memorySnapshots(files);
    site = _Site();
  });

  ProviderContainer app([AppSettings settings = const AppSettings()]) =>
      containerWith(settings, [sourceProvider(SiteId.v2ex).overrideWithValue(site)]);

  group('what is saved', () {
    test('a thread comes back as it was sent', () async {
      final c = app();
      c.listen(repliesProvider(ref), (_, _) {});
      await c.read(repliesProvider(ref).future);
      await pumpEventQueue();

      site.down = true;
      final c2 = app();
      final detail = await c2.read(topicDetailProvider(ref).future);
      expect(detail.title, '新的帖子');
      expect(detail.content, '<p>新正文</p>');
      expect(detail.replyCount, 2);
      expect(detail.savedAt, isNotNull);
      expect(detail.liked, isTrue);
      expect(detail.canLike, isFalse,
          reason: 'nothing to press on a copy read offline');

      c2.listen(repliesProvider(ref), (_, _) {});
      final replies = await c2.read(repliesProvider(ref).future);
      final reply = replies.items.single;
      expect(reply.floor, 1);
      expect(reply.quote?.excerpt, '引用');
      expect(reply.children.single.content, '<p>楼中楼</p>');
      expect(replies.total, 2);
    });

    test('a copy from a build that shaped things differently is ignored',
        () async {
      final c = app();
      await c.read(topicDetailProvider(ref).future);
      await pumpEventQueue();
      for (final k in files.keys.toList()) {
        final data = jsonDecode(utf8.decode(files[k]!)) as Map<String, dynamic>;
        files[k] = Uint8List.fromList(utf8.encode(jsonEncode({...data, 'v': 0})));
      }
      site.down = true;
      expect(app().read(topicDetailProvider(ref).future),
          throwsA(isA<Exception>()));
    });

    test('a damaged copy is ignored', () async {
      await app().read(topicDetailProvider(ref).future);
      await pumpEventQueue();
      for (final k in files.keys.toList()) {
        files[k] = Uint8List.fromList(utf8.encode('{"v":1,"savedAt":'));
      }
      site.down = true;
      expect(app().read(topicDetailProvider(ref).future),
          throwsA(isA<Exception>()));
    });

    test("one reader's copy is never shown to another", () async {
      await app(const AppSettings(v2exToken: 'alice'))
          .read(topicDetailProvider(ref).future);
      await pumpEventQueue();
      site.down = true;
      expect(app(const AppSettings(v2exToken: 'bob'))
          .read(topicDetailProvider(ref).future), throwsA(isA<Exception>()));
      expect(
          (await app(const AppSettings(v2exToken: 'alice'))
                  .read(topicDetailProvider(ref).future))
              .savedAt,
          isNotNull);
    });

    test('nothing of the credential is written down', () async {
      await app(const AppSettings(v2exToken: 'secret-token'))
          .read(topicDetailProvider(ref).future);
      await pumpEventQueue();
      for (final k in files.keys) {
        expect('$k', isNot(contains('secret-token')));
        expect(utf8.decode(files[k]!), isNot(contains('secret-token')));
      }
    });
  });

  group('a list', () {
    test('opens from its copy, then shows what the site says', () async {
      final first = app();
      first.listen(feedProvider(key), (_, _) {});
      await first.read(feedProvider(key).future);
      await pumpEventQueue();

      site.label = '更新';
      final c = app();
      c.listen(feedProvider(key), (_, _) {});
      final opened = await c.read(feedProvider(key).future);
      expect(opened.items.first.title, '新帖 0');
      expect(opened.savedAt, isNotNull);
      expect(opened.refreshing, isTrue);
      expect(opened.items.first.author?.avatarUrl, 'https://a/neo.png');

      await pumpEventQueue();
      final now = c.read(feedProvider(key)).value!;
      expect(now.items.first.title, '更新帖 0');
      expect(now.savedAt, isNull);
      expect(now.refreshing, isFalse);
    });

    test('keeps its copy, and says why, when the site cannot be reached',
        () async {
      final first = app();
      first.listen(feedProvider(key), (_, _) {});
      await first.read(feedProvider(key).future);
      await pumpEventQueue();

      site.down = true;
      final c = app();
      c.listen(feedProvider(key), (_, _) {});
      await c.read(feedProvider(key).future);
      await pumpEventQueue();
      final now = c.read(feedProvider(key)).value!;
      expect(now.items, hasLength(3));
      expect(now.refreshing, isFalse);
      expect(now.refreshError, '连不上 V2EX');
    });

    test('with no copy, fails the way it always has', () async {
      site.down = true;
      final c = app();
      c.listen(feedProvider(key), (_, _) {});
      await expectLater(c.read(feedProvider(key).future), throwsException);
    });

    test('a refresh that fails keeps the list on screen', () async {
      final c = app();
      c.listen(feedProvider(key), (_, _) {});
      await c.read(feedProvider(key).future);
      site.down = true;
      await c.read(feedProvider(key).notifier).refresh();
      final now = c.read(feedProvider(key));
      expect(now.hasError, isFalse);
      expect(now.value!.items, hasLength(3));
      expect(now.value!.refreshError, '连不上 V2EX');
    });
  });

  group('a thread', () {
    test('is not replaced by its copy when the site says sign in first',
        () async {
      await app().read(topicDetailProvider(ref).future);
      await pumpEventQueue();
      site.signInNeeded = true;
      expect(app().read(topicDetailProvider(ref).future),
          throwsA(isA<AuthRequiredException>()));
    });

    testWidgets('read from its copy says so', (tester) async {
      await tester.runAsync(() async {
        await app().read(topicDetailProvider(ref).future);
        await pumpEventQueue();
      });
      site.down = true;
      final c = await pumpApp(
        tester,
        TopicDetailView(
            topic: ref, canGoBack: false, onBack: () {}, onOpenTopic: (_) {}),
        size: const Size(900, 700),
        overrides: [sourceProvider(SiteId.v2ex).overrideWithValue(site)],
      );
      expect(find.textContaining('没能连上站点'), findsOneWidget);
      expect(find.text('新的帖子'), findsWidgets);

      site.down = false;
      site.label = '更新';
      // The note's own button; the replies, never saved here, have theirs.
      await tester.tap(find.widgetWithText(TextButton, '重试'));
      await tester.pumpAndSettle();
      expect(find.textContaining('没能连上站点'), findsNothing);
      expect(find.text('更新的帖子'), findsWidgets);
      await disposeApp(tester, c);
    });
  });

  testWidgets('a list that could not be refreshed says so, and retries',
      (tester) async {
    final c = await pumpApp(
      tester,
      SizedBox(
        width: 392,
        height: 600,
        child: TopicListPane(site: SiteId.v2ex, sectionId: 'all', onOpen: (_) {}),
      ),
      size: const Size(800, 700),
      overrides: [sourceProvider(SiteId.v2ex).overrideWithValue(site)],
    );
    site.down = true;
    await c.read(feedProvider(key).notifier).refresh();
    await tester.pumpAndSettle();
    expect(find.text('新帖 0'), findsOneWidget);
    expect(find.textContaining('没能刷新：连不上 V2EX'), findsOneWidget);

    site.down = false;
    site.label = '更新';
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('更新帖 0'), findsOneWidget);
    expect(find.textContaining('没能刷新'), findsNothing);
  });
}
