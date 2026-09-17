// The reading pane can run long, so the toolbar offers a way back to the top.
// It only earns its place once there is something above the reader, and it has
// to actually move the pane, not merely exist.
import 'package:codora/app_theme.dart';
import 'package:codora/core/models.dart';
import 'package:codora/features/providers.dart';
import 'package:codora/features/topic_detail.dart';
import 'package:codora/widgets/chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A long post, so the pane has somewhere to scroll.
final longBody = List.generate(80, (i) => '<p>第 $i 段正文内容，够长以便滚动。</p>').join();

Future<void> pumpDetail(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      topicDetailProvider(const TopicRef(SiteId.v2ex, '1')).overrideWith(
        (ref) async => TopicDetail(
          site: SiteId.v2ex,
          id: '1',
          title: '一个很长的帖子',
          url: 'https://www.v2ex.com/t/1',
          content: longBody,
          author: const Author(name: 'neo'),
          createdAt: DateTime(2026, 9, 17),
        ),
      ),
      // Family notifiers are overridden as a whole, not per argument.
      repliesProvider.overrideWith(_NoReplies.new),
    ],
    child: MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: const Scaffold(
        body: SizedBox(
          height: 500,
          child: TopicDetailView(
            topic: TopicRef(SiteId.v2ex, '1'),
            canGoBack: false,
            onBack: _noop,
            onOpenTopic: _noopRef,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void _noop() {}
void _noopRef(TopicRef _) {}

class _NoReplies extends RepliesNotifier {
  @override
  Future<RepliesState> build(TopicRef arg) async =>
      const RepliesState(items: []);
}

Finder topButton() => find.ancestor(
      of: find.byIcon(Icons.vertical_align_top_rounded),
      matching: find.byType(QuietIconButton),
    );

/// Null when the button is disabled, which is how it says "already at the top".
VoidCallback? topButtonAction(WidgetTester tester) =>
    tester.widget<QuietIconButton>(topButton()).onPressed;

Color? topIconColour(WidgetTester tester) =>
    tester.widget<Icon>(find.byIcon(Icons.vertical_align_top_rounded)).color;

/// The cursor the button itself declares. Tooltip wraps its child in a mouse
/// region of its own that defers, so the first match is not the right one.
MouseCursor topButtonCursor(WidgetTester tester) => tester
    .widgetList<MouseRegion>(find.descendant(
      of: topButton(),
      matching: find.byType(MouseRegion),
    ))
    .map((r) => r.cursor)
    .firstWhere((c) => c != MouseCursor.defer);

ScrollableState paneScroller(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first);

void main() {
  testWidgets('it sits next to reload, before the link actions',
      (tester) async {
    await pumpDetail(tester);
    final buttons = tester
        .widgetList<QuietIconButton>(find.byType(QuietIconButton))
        .map((b) => b.icon)
        .toList();
    expect(buttons, contains(Icons.vertical_align_top_rounded));
    expect(
      buttons.indexOf(Icons.vertical_align_top_rounded),
      buttons.indexOf(Icons.refresh_rounded) + 1,
      reason: 'it belongs immediately to the right of reload',
    );
    expect(
      buttons.indexOf(Icons.vertical_align_top_rounded),
      lessThan(buttons.indexOf(Icons.link_rounded)),
    );
  });

  testWidgets('it stays visible but disabled at the top of a post',
      (tester) async {
    await pumpDetail(tester);
    expect(topButton(), findsOneWidget,
        reason: 'it keeps its place so the toolbar does not reflow');
    expect(topButtonAction(tester), isNull,
        reason: 'there is nothing above to go back to');
  });

  testWidgets('at the top it is greyed and refuses the pointer',
      (tester) async {
    await pumpDetail(tester);
    expect(topIconColour(tester), Palette.dark.inkFaint,
        reason: 'the disabled tone, dimmer than an available action');
    expect(topButtonCursor(tester), SystemMouseCursors.forbidden);
  });

  testWidgets('it becomes available once the reader has scrolled down',
      (tester) async {
    await pumpDetail(tester);
    paneScroller(tester).position.jumpTo(600);
    await tester.pumpAndSettle();
    expect(topButtonAction(tester), isNotNull);
    expect(topIconColour(tester), Palette.dark.inkMuted);
    expect(topButtonCursor(tester), SystemMouseCursors.click);
  });

  testWidgets('a small scroll leaves it disabled', (tester) async {
    await pumpDetail(tester);
    paneScroller(tester).position.jumpTo(120);
    await tester.pumpAndSettle();
    expect(topButtonAction(tester), isNull,
        reason: 'it would scroll almost nowhere');
  });

  testWidgets('its tooltip explains why it is unavailable', (tester) async {
    await pumpDetail(tester);
    expect(tester.widget<QuietIconButton>(topButton()).tooltip, '已经在顶部');

    paneScroller(tester).position.jumpTo(600);
    await tester.pumpAndSettle();
    expect(tester.widget<QuietIconButton>(topButton()).tooltip, '回到顶部');
  });

  testWidgets('pressing it returns the pane to the top', (tester) async {
    await pumpDetail(tester);
    paneScroller(tester).position.jumpTo(900);
    await tester.pumpAndSettle();
    expect(paneScroller(tester).position.pixels, 900);

    await tester.tap(find.byIcon(Icons.vertical_align_top_rounded));
    await tester.pumpAndSettle();
    expect(paneScroller(tester).position.pixels, 0);
  });

  testWidgets('it glides rather than jumping', (tester) async {
    await pumpDetail(tester);
    paneScroller(tester).position.jumpTo(900);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.vertical_align_top_rounded));
    await tester.pump();
    await tester.pump(Motion.swap ~/ 2);
    final midway = paneScroller(tester).position.pixels;
    expect(midway, greaterThan(0));
    expect(midway, lessThan(900), reason: 'it should be on its way, animating');

    await tester.pumpAndSettle();
    expect(paneScroller(tester).position.pixels, 0);
  });

  testWidgets('pressing it while disabled does nothing', (tester) async {
    await pumpDetail(tester);
    await tester.tap(find.byIcon(Icons.vertical_align_top_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(paneScroller(tester).position.pixels, 0);
  });
}
