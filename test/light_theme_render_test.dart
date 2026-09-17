// Most widget tests run in the dark theme, so a palette change can look fine
// there and misbehave on white. These draw the pieces that carry colour in
// both themes and check what they actually paint.
import 'dart:io';

import 'package:codora/app_theme.dart';
import 'package:codora/core/models.dart';
import 'package:codora/features/topic_detail.dart';
import 'package:codora/features/topic_list.dart';
import 'package:codora/widgets/post_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TopicSummary sample({bool read = false}) => TopicSummary(
      site: SiteId.v2ex,
      id: '1',
      title: '一个标题',
      url: 'https://www.v2ex.com/t/1',
      excerpt: '一段摘要',
      author: const Author(name: 'neo'),
      sectionLabel: '程序员',
      replyCount: 42,
      lastActiveAt: DateTime(2026, 9, 17, 11, 27, 6),
    );

Future<void> pump(WidgetTester tester, Brightness brightness, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(brightness),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 420, child: child),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  for (final brightness in Brightness.values) {
    final name = brightness.name;
    final palette =
        brightness == Brightness.dark ? Palette.dark : Palette.light;

    testWidgets('a topic card draws in $name', (tester) async {
      await pump(tester, brightness,
          TopicCard(topic: sample(), selected: false, onTap: () {}));
      expect(tester.takeException(), isNull);

      final title = tester.widget<Text>(find.text('一个标题'));
      expect(title.style?.color, palette.ink);
    });

    testWidgets('a selected card draws in $name', (tester) async {
      await pump(tester, brightness,
          TopicCard(topic: sample(), selected: true, onTap: () {}));
      expect(tester.takeException(), isNull);
      // On a filled card the title flips to the colour meant for that fill.
      expect(tester.widget<Text>(find.text('一个标题')).style?.color,
          palette.accentInk);
    });

    testWidgets('a read card dims in $name', (tester) async {
      await pump(tester, brightness,
          TopicCard(topic: sample(), selected: false, read: true, onTap: () {}));
      expect(tester.widget<Text>(find.text('一个标题')).style?.color,
          palette.inkMuted);
    });

    testWidgets('a post header draws in $name', (tester) async {
      await pump(
        tester,
        brightness,
        CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: PostHeader(
              detail: TopicDetail(
                site: SiteId.juejin,
                id: '1',
                title: '标题',
                url: 'https://juejin.cn/post/1',
                content: '<p>正文</p>',
                author: const Author(name: '张三', tagline: '某公司 · 工程师'),
                sectionLabel: '后端',
                viewCount: 1200,
                likeCount: 34,
                createdAt: DateTime(2026, 9, 17),
              ),
            ),
          ),
        ]),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a post body draws in $name', (tester) async {
      await pump(
        tester,
        brightness,
        SingleChildScrollView(
          child: PostBody(
            content: File('test/fixtures/linuxdo_post.html').readAsStringSync(),
            format: BodyFormat.html,
            baseUrl: Uri.parse('https://linux.do'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a quoted reply draws in $name', (tester) async {
      await pump(
        tester,
        brightness,
        ReplyTile(
          reply: Reply(
            id: '1',
            content: '<p>回复正文</p>',
            author: const Author(name: 'someone'),
            createdAt: DateTime(2026, 9, 17),
            floor: 5,
            likeCount: 3,
            quote: const ReplyQuote(author: 'other', floor: 4, excerpt: '上一句'),
          ),
          baseUrl: Uri.parse('https://www.v2ex.com'),
          onTopicLink: (_) => false,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('#5'), findsOneWidget);
      expect(find.text('other'), findsOneWidget);
    });
  }
}
