// The meta row of a topic card is easy to break: author, board and timestamp
// all sit on one line, and giving each its own flexible slot splits the
// leftover width between them, which leaves the time floating in the middle.
import 'package:codora/app_theme.dart';
import 'package:codora/core/models.dart';
import 'package:codora/features/topic_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const cardWidth = 392.0;

TopicSummary sample({String? author, String? board, String title = '标题'}) =>
    TopicSummary(
      site: SiteId.v2ex,
      id: '1',
      title: title,
      url: 'https://www.v2ex.com/t/1',
      excerpt: '一段摘要',
      author: author == null ? null : Author(name: author),
      sectionLabel: board,
      replyCount: 12,
      lastActiveAt: DateTime.now().subtract(const Duration(minutes: 11)),
    );

Future<void> pumpCard(WidgetTester tester, TopicSummary topic,
    {bool read = false, bool selected = false}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: cardWidth,
          child: TopicCard(
              topic: topic, selected: selected, read: read, onTap: () {}),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// Gap between the timestamp's right edge and the card's inner right edge.
double gapAfterTime(WidgetTester tester) {
  final time = find.textContaining('分钟前');
  expect(time, findsOneWidget);
  final card = tester.getRect(find.byType(TopicCard));
  return card.right - tester.getRect(time).right;
}

void main() {
  testWidgets('the timestamp holds the right edge', (tester) async {
    await pumpCard(tester, sample(author: 'neo', board: '运营反馈'));
    // Only the card's own horizontal padding should separate them.
    expect(gapAfterTime(tester), lessThan(20));
  });

  testWidgets('short metadata does not strand the timestamp', (tester) async {
    // The bug showed up worst here: little text on the left, so a three-way
    // flex split left a wide gap to the right of the time.
    await pumpCard(tester, sample(author: 'a', board: 'b'));
    expect(gapAfterTime(tester), lessThan(20));
  });

  testWidgets('a card without author or board still right-aligns the time',
      (tester) async {
    await pumpCard(tester, sample());
    expect(gapAfterTime(tester), lessThan(20));
  });

  testWidgets('a long author name is truncated, not pushed over the time',
      (tester) async {
    await pumpCard(tester, sample(author: '这是一个非常非常长的用户名用来测试溢出行为', board: '一个同样很长的板块名称'));
    expect(tester.takeException(), isNull, reason: 'the row must not overflow');
    expect(gapAfterTime(tester), lessThan(20));
  });

  testWidgets('the old three-way flex split is what stranded the time',
      (tester) async {
    // Guards the reasoning behind the fix rather than the fix itself: with
    // author, board and Spacer each claiming one flex slot, the leftover width
    // is divided three ways and the surplus piles up after the timestamp.
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: cardWidth,
            child: Row(children: [
              const Flexible(child: Text('a')),
              const SizedBox(width: 10),
              const Flexible(child: Text('b')),
              const Spacer(),
              const Text('11 分钟前'),
            ]),
          ),
        ),
      ),
    ));
    await tester.pump();

    final row = tester.getRect(find.byType(SizedBox).first);
    final time = tester.getRect(find.text('11 分钟前'));
    expect(row.right - time.right, greaterThan(100),
        reason: 'the old layout left a wide gap; the card must not do this');
  });

  group('read state', () {
    TopicSummary post() => sample(author: 'neo', board: '运营反馈', title: '一个帖子');

    Text titleOf(WidgetTester tester) =>
        tester.widget<Text>(find.text('一个帖子'));

    testWidgets('an unread post is marked with a dot', (tester) async {
      await pumpCard(tester, post(), read: false);
      final dots = tester.widgetList<Container>(find.descendant(
        of: find.byType(TopicCard),
        matching: find.byType(Container),
      )).where((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.shape == BoxShape.circle;
      });
      expect(dots, isNotEmpty, reason: 'unread posts carry a dot');
    });

    testWidgets('a read post loses the dot', (tester) async {
      await pumpCard(tester, post(), read: true);
      final dots = tester.widgetList<Container>(find.descendant(
        of: find.byType(TopicCard),
        matching: find.byType(Container),
      )).where((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.shape == BoxShape.circle;
      });
      expect(dots, isEmpty);
    });

    testWidgets('a read title is dimmer and lighter than an unread one',
        (tester) async {
      await pumpCard(tester, post(), read: false);
      final unread = titleOf(tester).style!;

      await pumpCard(tester, post(), read: true);
      final read = titleOf(tester).style!;

      expect(read.color, isNot(unread.color), reason: 'it should dim');
      expect(read.color, Palette.dark.inkMuted);
      expect(read.fontWeight!.value, lessThan(unread.fontWeight!.value));
    });

    testWidgets('selection still wins over read styling', (tester) async {
      await pumpCard(tester, post(), read: true, selected: true);
      // A selected card is lavender, so its title must stay readable on it
      // rather than staying dimmed.
      expect(titleOf(tester).style!.color, Palette.dark.accentInk);
    });
  });
}
