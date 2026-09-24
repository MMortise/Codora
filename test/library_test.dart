// Topics can be bookmarked, every thread read goes into a history, and both
// are one click away on the rail. Sites that can be searched are searched in
// place of a board; one that cannot hands the words to a search engine.
import 'package:codora/core/forum_source.dart';
import 'package:codora/core/library.dart';
import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/features/library_page.dart';
import 'package:codora/features/providers.dart';
import 'package:codora/features/shell.dart';
import 'package:codora/features/topic_detail.dart';
import 'package:codora/features/topic_list.dart';
import 'package:codora/sources/juejin_source.dart';
import 'package:codora/sources/linuxdo_source.dart';
import 'package:codora/sources/v2ex_source.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

SavedTopic saved(String id, {SiteId site = SiteId.v2ex, String? title}) =>
    SavedTopic(
      site: site,
      id: id,
      title: title ?? '帖子 $id',
      url: 'https://www.v2ex.com/t/$id',
      author: 'neo',
      at: DateTime(2026, 9, 1),
    );

/// A site with a board, a search, and threads titled by their id.
class _Searchable extends FakeSource {
  _Searchable() : super(null);
  final queries = <(String, String?)>[];

  @override
  Future<List<Section>> sections() async =>
      const [Section(id: 'all', title: '全部')];

  TopicSummary _topic(String id, String title) => TopicSummary(
      site: SiteId.v2ex, id: id, title: title, url: 'https://www.v2ex.com/t/$id');

  @override
  Future<PageResult<TopicSummary>> fetchTopics(Section s,
          {String? cursor}) async =>
      PageResult(items: [_topic('1', '板块里的帖子')]);

  @override
  SearchTopics? get search => (query, {cursor}) async {
        queries.add((query, cursor));
        return PageResult(
          items: [_topic('s${cursor ?? 0}', '关于 $query 的帖子')],
          nextCursor: cursor == null ? '2' : null,
        );
      };

  @override
  Future<TopicDetail> fetchTopic(String id) async => TopicDetail(
        site: SiteId.v2ex,
        id: id,
        title: '帖子 $id',
        url: 'https://www.v2ex.com/t/$id',
        content: '<p>正文</p>',
        author: const Author(name: 'neo'),
      );

  @override
  Future<PageResult<Reply>> fetchReplies(String id, {String? cursor}) async =>
      const PageResult(items: []);
}

void main() {
  resetBootstrapState();

  group('what is kept', () {
    test('a bookmark goes in once, and comes out again', () {
      var l = const Library().toggleBookmark(saved('1'));
      expect(l.isBookmarked(const TopicRef(SiteId.v2ex, '1')), isTrue);
      l = l.toggleBookmark(saved('2')).toggleBookmark(saved('1'));
      expect(l.bookmarks.map((b) => b.id), ['2']);
    });

    test('the same id on two sites is two topics', () {
      final l = const Library()
          .toggleBookmark(saved('1'))
          .toggleBookmark(saved('1', site: SiteId.linuxdo));
      expect(l.bookmarks, hasLength(2));
    });

    test('reading a topic again moves it to the top of the history', () {
      final l = const Library()
          .withVisit(saved('1'))
          .withVisit(saved('2'))
          .withVisit(saved('1'));
      expect(l.history.map((h) => h.id), ['1', '2']);
    });

    test('the history reaches back only so far', () {
      var l = const Library();
      for (var i = 0; i < Library.historyLimit + 20; i++) {
        l = l.withVisit(saved('$i'));
      }
      expect(l.history, hasLength(Library.historyLimit));
      expect(l.history.first.id, '${Library.historyLimit + 19}');
    });

    test('both survive a restart', () async {
      await const Library()
          .toggleBookmark(saved('1', title: '一个"引号"和换行\n'))
          .withVisit(saved('2', site: SiteId.juejin))
          .save();
      final l = await Library.load();
      expect(l.bookmarks.single.title, '一个"引号"和换行\n');
      expect(l.history.single.site, SiteId.juejin);
      expect(l.history.single.at, DateTime(2026, 9, 1));
    });

    test('an entry from an unknown site, or a damaged one, is dropped',
        () async {
      SharedPreferences.setMockInitialValues({
        'bookmarks': [
          '{"site":"nowhere","id":"1","title":"t","url":"u","at":"2026-01-01"}',
          'not json',
          '{"site":"v2ex","id":"2","title":"t","url":"u","at":"2026-01-01"}',
        ],
      });
      expect((await Library.load()).bookmarks.map((b) => b.id), ['2']);
    });
  });

  /// The top bar is a window drag area, which also listens for a double
  /// click; a single one there lands once that could no longer be one.
  Future<void> openSearch(WidgetTester tester) async {
    await tester.tap(find.byTooltip('搜索 V2EX'));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
  }

  group('searching', () {
    test('linux.do: results in order of relevance, with what matched',
        () {
      final source = LinuxDoSource(
          cookie: 'cf_clearance=a', userAgent: kDesktopUserAgent);
      final page = source.parseSearch({
        'posts': [
          {'topic_id': 20, 'blurb': '说到 <b>Flutter</b> 桌面', 'username': 'neo',
            'avatar_template': '/user_avatar/linux.do/neo/{size}/1.png'},
          {'topic_id': 10, 'blurb': '另一个', 'username': 'trinity'},
          {'topic_id': 20, 'blurb': '同一帖的第二条', 'username': 'morpheus'},
        ],
        'topics': [
          {'id': 10, 'title': '十', 'slug': 'ten', 'posts_count': 3},
          {'id': 20, 'fancy_title': '二十', 'slug': 'twenty', 'posts_count': 1},
          {'id': 30, 'title': '只在标题里', 'slug': 'thirty', 'posts_count': 5},
        ],
        'grouped_search_result': {'more_full_page_results': true},
      }, page: 1);
      expect(page.items.map((t) => t.id), ['20', '10', '30']);
      final first = page.items.first;
      expect(first.title, '二十');
      expect(first.url, 'https://linux.do/t/twenty/20');
      expect(first.excerpt, '说到 Flutter 桌面');
      expect(first.author?.name, 'neo');
      expect(first.replyCount, 0);
      expect(page.items.last.author, isNull);
      expect(page.nextCursor, '2');
    });

    test('linux.do: the last page says so', () {
      final page = LinuxDoSource(
              cookie: 'cf_clearance=a', userAgent: kDesktopUserAgent)
          .parseSearch({'posts': [], 'topics': []}, page: 3);
      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
    });

    test('linux.do is searched only once it can be read', () {
      expect(LinuxDoSource(cookie: '', userAgent: kDesktopUserAgent).search,
          isNull);
      expect(
          LinuxDoSource(cookie: 'cf_clearance=a', userAgent: kDesktopUserAgent)
              .search,
          isNotNull);
    });

    test('Juejin: articles out of whatever the results hold', () {
      final page = JuejinSource().parseSearch({
        'data': [
          {
            'result_type': 2,
            'result_model': {
              'article_id': '7300',
              'article_info': {
                'title': 'Flutter 桌面实践',
                'brief_content': '简介',
                'comment_count': 4,
              },
              'author_user_info': {'user_name': '掘友', 'user_id': '9'},
              'category': {'category_name': '前端'},
            },
          },
          {'result_type': 1, 'result_model': {'user_id': '1'}},
        ],
        'cursor': '20',
        'has_more': true,
      });
      final t = page.items.single;
      expect(t.id, '7300');
      expect(t.url, 'https://juejin.cn/post/7300');
      expect(t.author?.name, '掘友');
      expect(t.sectionLabel, '前端');
      expect(t.replyCount, 4);
      expect(page.nextCursor, '20');
    });

    test('V2EX hands the words to a search engine instead', () {
      final source = V2exSource(token: '', proxy: '');
      expect(source.search, isNull);
      final page = source.searchPage('flutter 桌面')!;
      expect(page.host, 'www.bing.com');
      expect(page.queryParameters['q'], 'site:v2ex.com/t flutter 桌面');
    });

    test('a search pages like a board', () async {
      final site = _Searchable();
      final c = containerWith(const AppSettings(),
          [sourceProvider(SiteId.v2ex).overrideWithValue(site)]);
      final key = FeedKey(SiteId.v2ex, searchSectionId('flutter'));
      c.listen(feedProvider(key), (_, _) {});
      final first = await c.read(feedProvider(key).future);
      expect(first.items.single.title, '关于 flutter 的帖子');
      await c.read(feedProvider(key).notifier).loadMore();
      expect(c.read(feedProvider(key)).value!.items, hasLength(2));
      expect(site.queries, [('flutter', null), ('flutter', '2')]);
    });

    test('a search id is told apart from a board', () {
      expect(searchQueryOf(searchSectionId('a:b')), 'a:b');
      expect(searchQueryOf('c:rust:12'), isNull);
    });

    testWidgets('shows results in place of the board, until a board is picked',
        (tester) async {
      final c = await pumpApp(
        tester,
        const SitePage(site: SiteId.v2ex),
        size: const Size(1200, 800),
        overrides: [sourceProvider(SiteId.v2ex).overrideWithValue(_Searchable())],
      );
      expect(find.text('板块里的帖子'), findsOneWidget);

      await openSearch(tester);
      await tester.enterText(find.byType(TextField), '  flutter ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(c.read(searchQueryProvider(SiteId.v2ex)), 'flutter');
      expect(find.text('关于 flutter 的帖子'), findsOneWidget);
      expect(find.text('板块里的帖子'), findsNothing);

      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      expect(c.read(searchQueryProvider(SiteId.v2ex)), isNull);
      expect(find.text('板块里的帖子'), findsOneWidget);
      await disposeApp(tester, c);
    });

    testWidgets('closes with escape', (tester) async {
      final c = await pumpApp(
        tester,
        const SitePage(site: SiteId.v2ex),
        size: const Size(1200, 800),
        overrides: [sourceProvider(SiteId.v2ex).overrideWithValue(_Searchable())],
      );
      await openSearch(tester);
      await tester.enterText(find.byType(TextField), 'flutter');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.read(searchQueryProvider(SiteId.v2ex)), isNull);
      expect(find.byTooltip('搜索 V2EX'), findsOneWidget);
      await disposeApp(tester, c);
    });
  });

  group('the reading pane', () {
    Future<ProviderContainer> pumpThread(WidgetTester tester) => pumpApp(
          tester,
          TopicDetailView(
            topic: const TopicRef(SiteId.v2ex, '7'),
            canGoBack: false,
            onBack: () {},
            onOpenTopic: (_) {},
          ),
          size: const Size(900, 700),
          overrides: [
            sourceProvider(SiteId.v2ex).overrideWithValue(_Searchable())
          ],
        );

    testWidgets('bookmarks the thread, and takes it back', (tester) async {
      final c = await pumpThread(tester);
      await tester.tap(find.byTooltip('收藏'));
      await tester.pumpAndSettle();
      final kept = c.read(libraryProvider).bookmarks.single;
      expect(kept.title, '帖子 7');
      expect(kept.author, 'neo');
      expect(find.byTooltip('取消收藏'), findsOneWidget);

      await tester.tap(find.byTooltip('取消收藏'));
      await tester.pumpAndSettle();
      expect(c.read(libraryProvider).bookmarks, isEmpty);
    });

    testWidgets('puts every thread read into the history', (tester) async {
      final c = await pumpThread(tester);
      expect(c.read(libraryProvider).history.single.id, '7');
    });
  });

  group('the page', () {
    Future<ProviderContainer> pumpPage(WidgetTester tester, Library l) {
      Library.bootstrap = l;
      return pumpApp(
        tester,
        const LibraryPage(),
        size: const Size(1200, 800),
        overrides: [sourceProvider(SiteId.v2ex).overrideWithValue(_Searchable())],
      );
    }

    testWidgets('lists bookmarks and history apart', (tester) async {
      await pumpPage(
          tester,
          const Library()
              .toggleBookmark(saved('1', title: '收着的'))
              .withVisit(saved('2', title: '读过的')));
      expect(find.text('收着的'), findsOneWidget);
      expect(find.text('读过的'), findsNothing);
      await tester.tap(find.text('历史'));
      await tester.pumpAndSettle();
      expect(find.text('读过的'), findsOneWidget);
    });

    testWidgets('says where bookmarks come from when there are none',
        (tester) async {
      await pumpPage(tester, const Library());
      expect(find.textContaining('还没有收藏'), findsOneWidget);
    });

    testWidgets('opens one beside the list', (tester) async {
      await pumpPage(tester, const Library().toggleBookmark(saved('9')));
      await tester.tap(find.byType(TopicCard));
      await tester.pumpAndSettle();
      expect(find.byType(TopicDetailView), findsOneWidget);
      expect(find.textContaining('正文', findRichText: true), findsOneWidget);
    });

    testWidgets('clears the history', (tester) async {
      final c = await pumpPage(tester, const Library().withVisit(saved('2')));
      await tester.tap(find.text('历史'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空历史'));
      await tester.pumpAndSettle();
      expect(c.read(libraryProvider).history, isEmpty);
      expect(find.textContaining('还没有浏览记录'), findsOneWidget);
    });
  });
}
