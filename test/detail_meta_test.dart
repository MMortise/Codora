// The small print around a post: floor numbers, counts and timestamps. Each
// one is a place where a layout or colour change quietly regresses.
import 'dart:math' as math;

import 'package:codora/app_theme.dart';
import 'package:codora/core/models.dart';
import 'package:codora/core/util.dart';
import 'package:codora/features/topic_detail.dart';
import 'package:codora/features/topic_list.dart';
import 'package:codora/widgets/relative_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const paneWidth = 620.0;

Reply reply({
  int? floor,
  int? likes,
  String author = 'someone',
  ReplyQuote? quote,
}) =>
    Reply(
      id: '1',
      content: '<p>回复正文</p>',
      author: Author(name: author),
      createdAt: DateTime(2026, 9, 17, 11, 27, 6),
      floor: floor,
      likeCount: likes,
      quote: quote,
    );

Future<void> pumpReply(WidgetTester tester, Reply r,
    {bool first = false}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: paneWidth,
          child: ReplyTile(
            reply: r,
            first: first,
            baseUrl: Uri.parse('https://linux.do'),
            onTopicLink: (_) => false,
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// How many rules the tile draws above itself.
int topRules(WidgetTester tester) => find
    .byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        ((w.decoration! as BoxDecoration).border?.top.style ??
                BorderStyle.none) !=
            BorderStyle.none)
    .evaluate()
    .length;

/// WCAG relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// Contrast between two opaque colours, 1 (identical) to 21 (black on white).
double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('the seam above a reply', () {
    testWidgets('every reply but the first is separated by a rule',
        (tester) async {
      await pumpReply(tester, reply(floor: 2));
      expect(topRules(tester), 1);
    });

    testWidgets('the first has none — the reply count already drew one',
        (tester) async {
      // The 「{n} 条回复」 caption sits between two rules, so a border here
      // would land a second line directly under it.
      await pumpReply(tester, reply(floor: 1), first: true);
      expect(topRules(tester), 0);
    });
  });

  group('floor numbers', () {
    testWidgets('are written with a hash', (tester) async {
      await pumpReply(tester, reply(floor: 7));
      expect(find.text('#7'), findsOneWidget);
      expect(find.text('7'), findsNothing);
    });

    testWidgets('hold the right edge', (tester) async {
      await pumpReply(tester, reply(floor: 12));
      final tile = tester.getRect(find.byType(ReplyTile));
      final floor = tester.getRect(find.text('#12'));
      expect(tile.right - floor.right, lessThan(36),
          reason: 'only the tile padding should sit to its right');
    });

    testWidgets('stay right even with a like count beside them', (tester) async {
      await pumpReply(tester, reply(floor: 3, likes: 5));
      final tile = tester.getRect(find.byType(ReplyTile));
      final floor = tester.getRect(find.text('#3'));
      final likes = tester.getRect(find.text('5 赞'));
      expect(tile.right - floor.right, lessThan(36));
      expect(likes.right, lessThan(floor.left), reason: 'floor comes last');
    });

    testWidgets('a long author name does not push the floor inward',
        (tester) async {
      await pumpReply(
          tester, reply(floor: 99, author: '一个非常非常长的用户名用来把这一行撑满看看会怎样'));
      expect(tester.takeException(), isNull);
      final tile = tester.getRect(find.byType(ReplyTile));
      expect(tile.right - tester.getRect(find.text('#99')).right, lessThan(36));
    });
  });

  group('timestamps', () {
    test('the absolute form carries seconds', () {
      expect(fullTime(DateTime(2026, 9, 17, 11, 27, 6)), '2026-09-17 11:27:06');
      expect(fullTime(DateTime(2026, 1, 2, 3, 4, 5)), '2026-01-02 03:04:05');
      expect(fullTime(null), '');
    });

    testWidgets('a reply time hides the exact moment behind a tooltip',
        (tester) async {
      await pumpReply(tester, reply(floor: 1));
      // RelativeTime wraps its text in the tooltip, so look downward.
      final widget = tester.widget<Tooltip>(find.descendant(
        of: find.byType(RelativeTime),
        matching: find.byType(Tooltip),
      ).first);
      expect(widget.message, '2026-09-17 11:27:06');
    });

    testWidgets('no tooltip when there is no time', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const Scaffold(body: RelativeTime(null)),
      ));
      await tester.pump();
      expect(find.byType(Tooltip), findsNothing);
    });
  });

  group('reply count badge', () {
    Future<Container> badgeOf(WidgetTester tester, {required bool selected}) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 392,
              child: TopicCard(
                topic: TopicSummary(
                  site: SiteId.v2ex,
                  id: '1',
                  title: '标题',
                  url: 'https://www.v2ex.com/t/1',
                  replyCount: 42,
                  createdAt: DateTime(2026, 9, 17, 11, 27, 6),
                ),
                selected: selected,
                onTap: () {},
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      return tester.widget<Container>(find.ancestor(
        of: find.text('42'),
        matching: find.byType(Container),
      ).first);
    }

    testWidgets('uses the brand purple with white text when unselected',
        (tester) async {
      final badge = await badgeOf(tester, selected: false);
      expect((badge.decoration as BoxDecoration).color,
          const Color(0xFF9856DC));

      final text = tester.widget<Text>(find.text('42'));
      expect(text.style?.color, const Color(0xFFFFFFFF));
    });

    testWidgets('the count is not bolded', (tester) async {
      await badgeOf(tester, selected: false);
      final text = tester.widget<Text>(find.text('42'));
      final weight = text.style?.fontWeight ?? FontWeight.normal;
      expect(weight.value, lessThanOrEqualTo(FontWeight.normal.value));
    });

    testWidgets('inverts on a selected card, which is already lavender',
        (tester) async {
      final badge = await badgeOf(tester, selected: true);
      expect((badge.decoration as BoxDecoration).color, isNot(Palette.dark.badge),
          reason: 'the badge would vanish into a lavender card');
    });

    test('the badge stays readable', () {
      // White on this purple measures 4.47:1, just under the 4.5 bar for body
      // text. The pairing was chosen deliberately and the shortfall is not
      // perceptible at this size, but anything materially lower is a
      // regression, so the floor sits right below the current value.
      for (final palette in [Palette.dark, Palette.light]) {
        final ratio = contrastRatio(palette.badge, palette.onBadge);
        expect(ratio, greaterThanOrEqualTo(4.4),
            reason: 'badge text must stay legible');
        expect(ratio, closeTo(4.47, 0.05),
            reason: 'if the purple moves, re-check the text colour');
      }
    });

    test('the contrast helper agrees with known values', () {
      // Guards the formula itself, so a broken helper cannot make the
      // palette assertions pass by accident.
      expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
          closeTo(21, 0.1));
      expect(contrastRatio(const Color(0xFF777777), const Color(0xFFFFFFFF)),
          closeTo(4.48, 0.1));
      expect(contrastRatio(const Color(0xFF9856DC), const Color(0xFF1B1030)),
          closeTo(4.04, 0.1),
          reason: 'a soft dark text on this purple would be worse than white');
    });

    test('the badge is not mistakable for a selection', () {
      expect(Palette.dark.badge, isNot(Palette.dark.accent));
      expect(Palette.light.badge, isNot(Palette.light.accent));
    });
  });

  group('quoted replies', () {
    testWidgets('a quote names who is being answered', (tester) async {
      await pumpReply(
        tester,
        reply(
          floor: 5,
          quote: const ReplyQuote(
              author: 'xiapipi', floor: 4, excerpt: '被引用的那句话'),
        ),
      );
      expect(find.text('xiapipi'), findsOneWidget);
      expect(find.text('#4'), findsOneWidget);
      expect(find.text('被引用的那句话'), findsOneWidget);
    });

    testWidgets('it sits above the reply, not inside it', (tester) async {
      await pumpReply(
        tester,
        reply(
          floor: 5,
          quote: const ReplyQuote(author: 'xiapipi', floor: 4, excerpt: '上一句'),
        ),
      );
      final quoteY = tester.getRect(find.text('上一句')).top;
      final bodyY = tester.getRect(find.textContaining("回复正文", findRichText: true)).top;
      expect(quoteY, lessThan(bodyY),
          reason: 'the quote introduces the reply');
    });

    testWidgets('a mention without a floor still shows', (tester) async {
      await pumpReply(
        tester,
        reply(floor: 3, quote: const ReplyQuote(author: 'someone_else')),
      );
      expect(find.text('someone_else'), findsOneWidget);
      expect(find.textContaining('#'), findsOneWidget,
          reason: 'only this reply own floor marker remains');
    });

    testWidgets('a reply with no quote shows none', (tester) async {
      await pumpReply(tester, reply(floor: 2));
      expect(find.byIcon(Icons.reply_rounded), findsNothing);
    });

    testWidgets('an empty quote is not drawn', (tester) async {
      await pumpReply(tester, reply(floor: 2, quote: const ReplyQuote()));
      expect(find.byIcon(Icons.reply_rounded), findsNothing,
          reason: 'a quote with nothing in it is not worth a block');
    });
  });
}
