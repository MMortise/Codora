// The post header lays out an avatar, a name, an optional tagline, a time and
// a row of pills on one line. Authors differ a lot between sites, and a field
// that is empty on one site and long on another is exactly how this broke:
// Juejin authors carry a company and job title, the other two usually do not.
import 'package:codora/app_theme.dart';
import 'package:codora/core/models.dart';
import 'package:codora/features/topic_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TopicDetail detail({
  Author? author,
  String? section,
  int? views,
  int? likes,
}) =>
    TopicDetail(
      site: SiteId.juejin,
      id: '1',
      title: '一个标题',
      url: 'https://juejin.cn/post/1',
      content: '<p>正文</p>',
      author: author,
      sectionLabel: section,
      viewCount: views,
      likeCount: likes,
      createdAt: DateTime(2026, 9, 17, 11, 27, 6),
    );

Future<void> pumpDetail(WidgetTester tester, TopicDetail d,
    {double width = 620}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: PostHeader(detail: d)),
          ]),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('an author with a tagline lays out', (tester) async {
    // This is the Juejin shape, and the case that used to throw.
    await pumpDetail(
      tester,
      detail(
        author: const Author(name: '张三', tagline: '某公司 · 高级前端工程师'),
        section: '前端',
        views: 1200,
        likes: 34,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('张三'), findsOneWidget);
    expect(find.text('某公司 · 高级前端工程师'), findsOneWidget);
  });

  testWidgets('an author without a tagline lays out', (tester) async {
    await pumpDetail(tester, detail(author: const Author(name: 'neo')));
    expect(tester.takeException(), isNull);
    expect(find.text('neo'), findsOneWidget);
  });

  testWidgets('no author at all lays out', (tester) async {
    await pumpDetail(tester, detail());
    expect(tester.takeException(), isNull);
  });

  testWidgets('a very long tagline is truncated, not overflowing',
      (tester) async {
    await pumpDetail(
      tester,
      detail(
        author: const Author(
            name: '一个名字也相当长的作者',
            tagline: '一家名字非常非常长的公司 · 一个头衔也非常非常长的职位名称 · 还有更多的内容在后面'),
        section: '一个很长的板块名称',
        views: 999999,
        likes: 88888,
      ),
    );
    expect(tester.takeException(), isNull,
        reason: 'the header must not overflow, whatever the author carries');
  });

  testWidgets('every tagline shape Juejin actually serves lays out',
      (tester) async {
    // Sampled from the live recommend feed: 16 of 20 authors carried one,
    // which is why this site broke and the other two did not.
    const real = [
      '前端',
      '架构师',
      'Android 开发',
      '公众号：程序员Sunday',
      'kyriewen11 · 公众号',
      '菜鸡科技有限公司 · 前端开发工程师',
    ];
    for (final tagline in real) {
      for (final width in [620.0, 420.0]) {
        await pumpDetail(
          tester,
          detail(
            author: Author(name: 'someone', tagline: tagline),
            section: '后端',
            views: 5200,
            likes: 61,
          ),
          width: width,
        );
        expect(tester.takeException(), isNull,
            reason: '"$tagline" at ${width}px');
      }
    }
  });

  testWidgets('it survives a narrow pane', (tester) async {
    await pumpDetail(
      tester,
      detail(
        author: const Author(name: '张三', tagline: '某公司 · 高级前端工程师'),
        section: '前端',
        views: 1200,
        likes: 34,
      ),
      width: 320,
    );
    expect(tester.takeException(), isNull);
  });
}
