// A reader can keep topics out of every list: by board, by author, or by a
// word in the title. Blocking works on what is already loaded, keeps a
// thinned-out list from looking empty, and can always be taken back.
import 'package:codora/core/block_list.dart';
import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/features/block_panel.dart';
import 'package:codora/features/providers.dart';
import 'package:codora/features/topic_list.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

TopicSummary topic(String id,
        {String title = '标题',
        String? author,
        String? board,
        SiteId site = SiteId.v2ex}) =>
    TopicSummary(
      site: site,
      id: id,
      title: title,
      url: 'https://example.com/$id',
      author: author == null ? null : Author(name: author),
      sectionLabel: board,
    );

/// A feed of pages of twenty, each topic written by `a$page` in board
/// `b$page`, counting how often it is asked.
class _Pages extends FakeSource {
  _Pages({this.pages = 10}) : super(null);
  final int pages;
  int fetches = 0;

  @override
  Future<List<Section>> sections() async =>
      const [Section(id: 'all', title: '全部')];

  @override
  Future<PageResult<TopicSummary>> fetchTopics(Section s,
      {String? cursor}) async {
    fetches++;
    final page = int.tryParse(cursor ?? '') ?? 0;
    return PageResult(
      items: [
        for (var i = 0; i < 20; i++)
          topic('$page-$i',
              title: '第 $page 页第 $i 帖', author: 'a$page', board: 'b$page'),
      ],
      nextCursor: page + 1 < pages ? '${page + 1}' : null,
    );
  }
}

void main() {
  resetBootstrapState();

  group('the rules', () {
    test('an author is blocked on the site they were blocked on', () {
      final b = BlockList.empty.withAuthor(SiteId.v2ex, 'neo');
      expect(b.blocks(topic('1', author: 'neo')), isTrue);
      expect(b.blocks(topic('1', author: 'neo', site: SiteId.linuxdo)), isFalse,
          reason: 'the same name on another forum is somebody else');
      expect(b.blocks(topic('1', author: 'trinity')), isFalse);
    });

    test('so is a board', () {
      final b = BlockList.empty.withSection(SiteId.v2ex, '酷工作');
      expect(b.reasonFor(topic('1', board: '酷工作')), '节点 酷工作');
      expect(b.blocks(topic('1', board: '酷工作', site: SiteId.juejin)),
          isFalse);
    });

    test('a word is blocked in every title, whatever its case', () {
      final b = BlockList.empty.withKeyword('Rust');
      expect(b.blocks(topic('1', title: '为什么我放弃了 rust')), isTrue);
      expect(b.blocks(topic('1', title: 'RUST 周报', site: SiteId.linuxdo)),
          isTrue);
      expect(b.blocks(topic('1', title: 'Go 周报')), isFalse);
    });

    test('an empty word is not a rule', () {
      expect(BlockList.empty.withKeyword('   ').isEmpty, isTrue);
    });

    test('anything blocked can be taken back', () {
      final b = BlockList.empty
          .withKeyword('x')
          .withAuthor(SiteId.v2ex, 'neo')
          .withKeyword('x', blocked: false)
          .withAuthor(SiteId.v2ex, 'neo', blocked: false);
      expect(b, BlockList.empty);
    });

    test('they survive a restart', () async {
      await AppSettings(
        blocks: BlockList.empty
            .withKeyword('广告')
            .withAuthor(SiteId.linuxdo, 'bot')
            .withSection(SiteId.v2ex, '推广'),
      ).save();
      final loaded = await AppSettings.load();
      expect(loaded.blocks.keywords, {'广告'});
      expect(loaded.blocks.authors, {'linuxdo:bot'});
      expect(loaded.blocks.sections, {'v2ex:推广'});
    });

    test('an entry for a site this build does not know is dropped', () async {
      SharedPreferences.setMockInitialValues({
        'blockedAuthors': ['v2ex:neo', 'somewhere:else', 'garbage'],
      });
      final loaded = await AppSettings.load();
      expect(loaded.blocks.authors, {'v2ex:neo'});
    });
  });

  group('the feed', () {
    test('drops what is blocked without fetching again', () async {
      final source = _Pages();
      final c = containerWith(const AppSettings(), [
        sourceProvider(SiteId.v2ex).overrideWithValue(source),
      ]);
      const key = FeedKey(SiteId.v2ex, 'all');
      c.listen(visibleFeedProvider(key), (_, _) {});
      await c.read(feedProvider(key).future);
      expect(c.read(visibleFeedProvider(key)).value!.items, hasLength(20));

      await c.read(settingsProvider.notifier).patch((s) => s.copyWith(
          blocks: s.blocks.withKeyword('第 0 页第 1 帖')));
      final items = c.read(visibleFeedProvider(key)).value!.items;
      expect(items.map((t) => t.id), isNot(contains('0-1')));
      expect(items, hasLength(19));
      expect(source.fetches, 1);
    });
  });

  group('the list', () {
    Future<(ProviderContainer, _Pages)> pumpList(WidgetTester tester,
        {AppSettings settings = const AppSettings(), int pages = 10}) async {
      final source = _Pages(pages: pages);
      final c = await pumpApp(
        tester,
        SizedBox(
          width: 392,
          height: 600,
          child: TopicListPane(
              site: SiteId.v2ex, sectionId: 'all', onOpen: (_) {}),
        ),
        settings: settings,
        size: const Size(800, 700),
        overrides: [sourceProvider(SiteId.v2ex).overrideWithValue(source)],
      );
      return (c, source);
    }

    testWidgets('fetches on when a whole page is blocked', (tester) async {
      await pumpList(tester,
          settings: AppSettings(
              blocks: BlockList.empty.withAuthor(SiteId.v2ex, 'a0')));
      expect(find.text('第 1 页第 0 帖'), findsOneWidget);
      expect(find.text('第 0 页第 0 帖'), findsNothing);
    });

    testWidgets('but not to the end of a board blocked almost entirely',
        (tester) async {
      final (_, source) = await pumpList(tester,
          settings: AppSettings(
              blocks: BlockList.empty.withKeyword('帖')));
      // The first page, then five more in a row, then it waits to be asked.
      expect(source.fetches, 6);
      expect(find.text('加载更多'), findsOneWidget);
    });

    testWidgets('blocks an author from a right-click, and takes it back',
        (tester) async {
      final (c, _) = await pumpList(tester);
      await tester.tap(find.text('第 0 页第 0 帖'),
          buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('屏蔽作者「a0」'));
      await tester.pumpAndSettle();

      expect(c.read(settingsProvider).blocks.authors, {'v2ex:a0'});
      expect(find.text('第 0 页第 0 帖'), findsNothing);
      expect(find.text('已屏蔽作者「a0」'), findsOneWidget);

      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).blocks.isEmpty, isTrue);
      expect(find.text('第 0 页第 0 帖'), findsOneWidget);
    });

    testWidgets('blocks a board from a right-click', (tester) async {
      final (c, _) = await pumpList(tester);
      await tester.tap(find.text('第 0 页第 0 帖'),
          buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('屏蔽节点「b0」'));
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).blocks.sections, {'v2ex:b0'});
    });
  });

  group('the panel', () {
    testWidgets('adds a word, and lists what is blocked', (tester) async {
      final c = await pumpApp(
        tester,
        const SingleChildScrollView(child: BlockPanel()),
        settings: AppSettings(
            blocks: BlockList.empty
                .withAuthor(SiteId.linuxdo, 'bot')
                .withSection(SiteId.v2ex, '推广')),
        size: const Size(900, 900),
      );
      expect(find.text('Linux.do · bot'), findsOneWidget);
      expect(find.text('V2EX · 推广'), findsOneWidget);

      await tester.enterText(find.byType(TextField), ' 广告 ');
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).blocks.keywords, {'广告'});
      expect(find.widgetWithText(InputChip, '广告'), findsOneWidget);
    });

    testWidgets('takes one back', (tester) async {
      final c = await pumpApp(
        tester,
        const SingleChildScrollView(child: BlockPanel()),
        settings: AppSettings(
            blocks: BlockList.empty.withAuthor(SiteId.linuxdo, 'bot')),
        size: const Size(900, 900),
      );
      await tester.tap(find.byTooltip('不再屏蔽'));
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).blocks.isEmpty, isTrue);
      expect(find.text('还没有屏蔽任何作者'), findsOneWidget);
    });
  });
}
