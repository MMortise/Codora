// J and K pick the next card and bring it into view. Cards are as tall as
// their title and excerpt make them, and the list used to work out where a
// card was from one fixed height: the error grew with every card, until the
// one just picked sat somewhere off screen.
import 'package:codora/core/models.dart';
import 'package:codora/features/providers.dart';
import 'package:codora/features/topic_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A feed whose cards differ in height: some carry a long title and a long
/// excerpt, some neither.
class _TallAndShortFeed extends FakeSource {
  _TallAndShortFeed(this.count) : super(null);
  final int count;

  @override
  Future<List<Section>> sections() async =>
      const [Section(id: 'all', title: '全部')];

  @override
  Future<PageResult<TopicSummary>> fetchTopics(Section s,
          {String? cursor}) async =>
      PageResult(items: [
        for (var i = 0; i < count; i++)
          TopicSummary(
            site: SiteId.v2ex,
            id: '$i',
            title: i.isEven ? '第 $i 帖' : '第 $i 帖，${'一个很长的标题' * 6}',
            url: 'https://www.v2ex.com/t/$i',
            excerpt: i % 3 == 0 ? '一段很长的摘要' * 12 : null,
            replyCount: i,
          ),
      ]);
}

void main() {
  resetBootstrapState();

  Future<ProviderContainer> pumpList(WidgetTester tester, int count) async {
    late ProviderContainer container;
    container = await pumpApp(
      tester,
      Consumer(builder: (context, ref, _) {
        return SizedBox(
          width: 392,
          height: 600,
          child: TopicListPane(
            site: SiteId.v2ex,
            sectionId: 'all',
            onOpen: (t) => container
                .read(detailStackProvider(SiteId.v2ex).notifier)
                .state = [TopicRef(SiteId.v2ex, t.id)],
          ),
        );
      }),
      size: const Size(800, 700),
      overrides: [
        sourceProvider(SiteId.v2ex).overrideWithValue(_TallAndShortFeed(count)),
      ],
    );
    return container;
  }

  String? selected(ProviderContainer c) {
    final stack = c.read(detailStackProvider(SiteId.v2ex));
    return stack.isEmpty ? null : stack.first.id;
  }

  /// Whether the card for topic [id] is wholly inside the list.
  void expectOnScreen(WidgetTester tester, String id) {
    final list = tester.getRect(find.byType(ListView));
    final card = find.byWidgetPredicate((w) => w is TopicCard && w.topic.id == id);
    expect(card, findsOneWidget, reason: 'card $id should be built');
    final rect = tester.getRect(card);
    expect(rect.top, greaterThanOrEqualTo(list.top - 0.5),
        reason: 'card $id starts above the list');
    expect(rect.bottom, lessThanOrEqualTo(list.bottom + 0.5),
        reason: 'card $id runs below the list');
  }

  testWidgets('every card J lands on is on screen', (tester) async {
    final c = await pumpList(tester, 60);
    await tester.tap(find.byType(TopicCard).first);
    await tester.pumpAndSettle();
    expect(selected(c), '0');

    for (var i = 1; i < 60; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();
      expect(selected(c), '$i');
      expectOnScreen(tester, '$i');
    }
  });

  testWidgets('and every card K lands on, on the way back', (tester) async {
    final c = await pumpList(tester, 40);
    await tester.tap(find.byType(TopicCard).first);
    await tester.pumpAndSettle();
    for (var i = 1; i < 40; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.pumpAndSettle();
    }
    for (var i = 38; i >= 0; i--) {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pumpAndSettle();
      expect(selected(c), '$i');
      expectOnScreen(tester, '$i');
    }
  });

  testWidgets('a card already in view does not move the list', (tester) async {
    await pumpList(tester, 20);
    await tester.tap(find.byType(TopicCard).first);
    await tester.pumpAndSettle();
    final before = tester.getRect(
        find.byWidgetPredicate((w) => w is TopicCard && w.topic.id == '1'));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    final after = tester.getRect(
        find.byWidgetPredicate((w) => w is TopicCard && w.topic.id == '1'));
    expect(after.top, before.top);
  });

  testWidgets('J after scrolling far from the selection still finds it',
      (tester) async {
    final c = await pumpList(tester, 80);
    await tester.tap(find.byType(TopicCard).first);
    await tester.pumpAndSettle();
    // The reader wanders off to the bottom; card 1 is nowhere near built.
    await tester.drag(find.byType(ListView), const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((w) => w is TopicCard && w.topic.id == '1'),
        findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(selected(c), '1');
    expectOnScreen(tester, '1');
  });
}
