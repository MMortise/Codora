// A topic read once is remembered with how many replies it had and how far
// down the reader got. The list then says how many replies are new, and the
// thread offers to go straight to the first of them — or, with nothing new,
// back to where the reader left off.
import 'package:codora/core/models.dart';
import 'package:codora/core/read_log.dart';
import 'package:codora/features/providers.dart';
import 'package:codora/features/topic_detail.dart';
import 'package:codora/features/topic_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

/// A thread of [count] replies served twenty at a time, numbered by floor
/// unless [floors] is off — which is how Juejin's comments come.
class _Thread extends FakeSource {
  _Thread(this.count, {this.floors = true}) : super(null);
  final int count;
  final bool floors;

  @override
  Future<TopicDetail> fetchTopic(String id) async => TopicDetail(
        site: SiteId.v2ex,
        id: id,
        title: '一个帖子',
        url: 'https://www.v2ex.com/t/$id',
        content: '<p>正文</p>',
        replyCount: count,
      );

  @override
  Future<PageResult<Reply>> fetchReplies(String id, {String? cursor}) async {
    final from = int.tryParse(cursor ?? '') ?? 0;
    final to = (from + 20).clamp(0, count);
    return PageResult(
      items: [
        for (var i = from; i < to; i++)
          Reply(
            id: 'r$i',
            content: '<p>${'第 $i 条回复的内容。' * (i.isEven ? 1 : 6)}</p>',
            floor: floors ? i + 1 : null,
          ),
      ],
      nextCursor: to < count ? '$to' : null,
      total: count,
    );
  }
}

const topic = TopicRef(SiteId.v2ex, '7');

ReadLog readBefore({int? replies, int? position}) => ReadLog.bootstrap
    .markRead(SiteId.v2ex, '7')
    .withProgress(SiteId.v2ex, '7', replies: replies, position: position);

void main() {
  resetBootstrapState();

  group('what is kept', () {
    test('replies and position come back after a restart', () async {
      await ReadLog.bootstrap
          .markRead(SiteId.v2ex, '1')
          .withProgress(SiteId.v2ex, '1', replies: 12, position: 5)
          .save();
      final loaded = await ReadLog.load();
      final progress = loaded.progressOf(SiteId.v2ex, '1');
      expect(progress?.replies, 12);
      expect(progress?.position, 5);
    });

    test('a log from before this existed loads with nothing announced',
        () async {
      SharedPreferences.setMockInitialValues({
        'readTopics': ['v2ex:1', 'linuxdo:2'],
      });
      final loaded = await ReadLog.load();
      expect(loaded.contains(SiteId.v2ex, '1'), isTrue);
      expect(loaded.progressOf(SiteId.v2ex, '1'), isNull);
      expect(loaded.newReplies(SiteId.v2ex, '1', 99), 0);
    });

    test('and the list stays readable by a build from before', () async {
      await ReadLog.bootstrap
          .markRead(SiteId.v2ex, '1')
          .withProgress(SiteId.v2ex, '1', replies: 3)
          .save();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('readTopics'), ['v2ex:1']);
    });

    test('counts only what arrived since', () {
      final log = readBefore(replies: 10);
      expect(log.newReplies(SiteId.v2ex, '7', 13), 3);
      expect(log.newReplies(SiteId.v2ex, '7', 10), 0);
      // A thread that lost replies to moderation has nothing new.
      expect(log.newReplies(SiteId.v2ex, '7', 8), 0);
      expect(log.newReplies(SiteId.v2ex, '8', 13), 0, reason: 'never read');
    });

    test('marking read again keeps what was seen', () {
      final log = readBefore(replies: 10, position: 4)
          .markRead(SiteId.v2ex, '8')
          .markRead(SiteId.v2ex, '7');
      expect(log.progressOf(SiteId.v2ex, '7')?.replies, 10);
      expect(log.progressOf(SiteId.v2ex, '7')?.position, 4);
    });

    test('a topic not in the log records nothing', () {
      final log = ReadLog.bootstrap.withProgress(SiteId.v2ex, '9', replies: 3);
      expect(log.progressOf(SiteId.v2ex, '9'), isNull);
    });

    test('marking read leaves the log it came from as it was', () {
      final before = ReadLog.bootstrap.markRead(SiteId.v2ex, 'a');
      before.markRead(SiteId.v2ex, 'b').markRead(SiteId.v2ex, 'a');
      expect(before.length, 1);
      expect(before.contains(SiteId.v2ex, 'b'), isFalse);
    });

    test('clearing forgets it all', () {
      final log = readBefore(replies: 10).cleared();
      expect(log.progressOf(SiteId.v2ex, '7'), isNull);
    });
  });

  group('the list', () {
    Future<void> pumpCard(WidgetTester tester, {required int fresh}) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TopicCard(
              topic: const TopicSummary(
                  site: SiteId.v2ex,
                  id: '7',
                  title: '一个帖子',
                  url: 'https://www.v2ex.com/t/7',
                  replyCount: 13),
              selected: false,
              read: fresh == 0,
              newReplies: fresh,
              onTap: () {},
            ),
          ),
        ));

    testWidgets('says how many replies are new', (tester) async {
      await pumpCard(tester, fresh: 3);
      expect(find.text('+3'), findsOneWidget);
    });

    testWidgets('says nothing when none are', (tester) async {
      await pumpCard(tester, fresh: 0);
      expect(find.textContaining('+'), findsNothing);
    });
  });

  group('the thread', () {
    Future<ProviderContainer> pumpThread(WidgetTester tester,
        {required ReadLog log, _Thread? thread}) async {
      ReadLog.bootstrap = log;
      final c = await pumpApp(
        tester,
        TopicDetailView(
          topic: topic,
          canGoBack: false,
          onBack: () {},
          onOpenTopic: (_) {},
        ),
        size: const Size(900, 700),
        overrides: [
          sourceProvider(SiteId.v2ex).overrideWithValue(thread ?? _Thread(60)),
        ],
      );
      return c;
    }

    /// Where reply [floor]'s tile sits, relative to the top of the thread.
    double tileTop(WidgetTester tester, int floor) {
      final tile = find.byWidgetPredicate(
          (w) => w is ReplyTile && w.reply.floor == floor);
      expect(tile, findsOneWidget, reason: 'reply #$floor should be built');
      final pane = tester.getRect(find.byType(CustomScrollView));
      return tester.getRect(tile).top - pane.top;
    }

    testWidgets('offers the replies that arrived since, and goes to the first',
        (tester) async {
      await pumpThread(tester, log: readBefore(replies: 40));
      expect(find.text('20 条新回复'), findsOneWidget);

      await tester.tap(find.text('20 条新回复'));
      await tester.pumpAndSettle();
      expect(find.text('20 条新回复'), findsNothing);
      // The first new one is the 41st: it lands at the top of the thread.
      expect(tileTop(tester, 41), inInclusiveRange(0, 40));
    });

    testWidgets('once opened, the list has nothing new to announce',
        (tester) async {
      final c = await pumpThread(tester, log: readBefore(replies: 40));
      expect(
          c.read(readLogProvider).newReplies(SiteId.v2ex, '7', 60),
          0);
    });

    testWidgets('with nothing new, offers the reply the reader left on',
        (tester) async {
      await pumpThread(tester, log: readBefore(replies: 60, position: 25));
      expect(find.text('回到上次读到的第 26 条回复'), findsOneWidget);
      await tester.tap(find.text('回到上次读到的第 26 条回复'));
      await tester.pumpAndSettle();
      expect(tileTop(tester, 26), inInclusiveRange(0, 40));
    });

    testWidgets('offers nothing on a first visit', (tester) async {
      await pumpThread(tester, log: ReadLog.bootstrap.markRead(SiteId.v2ex, '7'));
      expect(find.textContaining('新回复'), findsNothing);
      expect(find.textContaining('回到上次'), findsNothing);
    });

    testWidgets('can be turned down', (tester) async {
      await pumpThread(tester, log: readBefore(replies: 40));
      await tester.tap(find.byTooltip('不用了'));
      await tester.pumpAndSettle();
      expect(find.text('20 条新回复'), findsNothing);
    });

    testWidgets('does not offer "new" where replies are not in order',
        (tester) async {
      await pumpThread(tester,
          log: readBefore(replies: 40, position: 3),
          thread: _Thread(60, floors: false));
      expect(find.textContaining('新回复'), findsNothing);
      expect(find.text('回到上次读到的第 4 条回复'), findsOneWidget);
    });

    testWidgets('remembers where the reader stopped', (tester) async {
      final c = await pumpThread(tester,
          log: ReadLog.bootstrap.markRead(SiteId.v2ex, '7'));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2500));
      await tester.pumpAndSettle();
      final position = c
          .read(readLogProvider)
          .progressOf(SiteId.v2ex, '7')
          ?.position;
      expect(position, isNotNull);
      expect(position, greaterThan(0));
    });
  });
}
