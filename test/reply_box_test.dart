// The box at the foot of a thread: when it is offered at all, what it does
// with what is written in it, and what happens when the forum says no.
import 'package:codora/core/models.dart';
import 'package:codora/features/providers.dart';
import 'package:codora/features/reply_box.dart';
import 'package:codora/features/topic_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _topic = TopicRef(SiteId.v2ex, '1');

Reply _sent(String content) =>
    Reply(id: '99', content: content, floor: 3, author: const Author(name: '我'));

/// A thread with one reply already in it, so a second one has somewhere to
/// land — and so the count has something to move from.
class _OneReply extends RepliesNotifier {
  @override
  Future<RepliesState> build(TopicRef arg) async => const RepliesState(
        items: [Reply(id: '1', content: '<p>先来的回复</p>', floor: 2)],
        total: 1,
      );
}

/// A thread that could not be read at all.
class _NoThread extends RepliesNotifier {
  @override
  Future<RepliesState> build(TopicRef arg) async => throw Exception('读不到');
}

/// By type rather than by its label: while a reply is on its way the button
/// holds a spinner instead, and a finder that needed the word would lose it
/// exactly when the test is asking what it does.
Finder sendButton() => find.byType(FilledButton);

void main() {
  resetBootstrapState();

  group('the box itself', () {
    Future<void> pumpBox(
      WidgetTester tester,
      Future<void> Function(String) onSend,
    ) async {
      await pumpApp(tester, ReplyBox(onSend: onSend),
          size: const Size(700, 400));
    }

    testWidgets('has nothing to send until something is written',
        (tester) async {
      await pumpBox(tester, (_) async {});
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '说得好');
      await tester.pump();
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNotNull);
    });

    testWidgets('whitespace is not something written', (tester) async {
      await pumpBox(tester, (_) async {});
      await tester.enterText(find.byType(TextField), '   \n  ');
      await tester.pump();
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);
    });

    testWidgets('hands over what was written, trimmed, and clears',
        (tester) async {
      String? got;
      await pumpBox(tester, (text) async => got = text);

      await tester.enterText(find.byType(TextField), '  说得好  ');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(got, '说得好');
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
          isEmpty, reason: 'it went, so it should not still be sitting there');
    });

    testWidgets('a refusal is shown, and what was written stays put',
        (tester) async {
      await pumpBox(tester, (_) async => throw Exception('正文似乎不清晰'));

      await tester.enterText(find.byType(TextField), '好');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // The forum's own sentence, without the class name in front of it.
      expect(find.text('正文似乎不清晰'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
          '好', reason: 'retyping it is not the fix');
    });

    testWidgets('editing it again drops the complaint about the old text',
        (tester) async {
      await pumpBox(tester, (_) async => throw Exception('正文似乎不清晰'));
      await tester.enterText(find.byType(TextField), '好');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();
      expect(find.text('正文似乎不清晰'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '好，我再写详细一点');
      await tester.pump();
      expect(find.text('正文似乎不清晰'), findsNothing);
    });

    testWidgets('nothing goes twice while the first is still going',
        (tester) async {
      var calls = 0;
      await pumpBox(tester, (_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.enterText(find.byType(TextField), '说得好');
      await tester.pump();

      await tester.tap(sendButton());
      await tester.pump();
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull,
          reason: 'it is on its way');

      await tester.tap(sendButton(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(calls, 1);
    });

    testWidgets('the modifier and return send it', (tester) async {
      // Plain return is a new paragraph — a forum reply is not a chat message
      // and is worth sending on purpose.
      String? got;
      await pumpBox(tester, (text) async => got = text);
      await tester.enterText(find.byType(TextField), '说得好');
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();
      expect(got, '说得好');
    });
  });

  group('where the pane offers one', () {
    Future<ProviderContainer> pumpPane(
      WidgetTester tester, {
      required FakeSource source,
      RepliesNotifier Function() thread = _OneReply.new,
    }) =>
        pumpApp(
          tester,
          const SizedBox(
            height: 560,
            child: TopicDetailView(
              topic: _topic,
              canGoBack: false,
              onBack: _noop,
              onOpenTopic: _noopRef,
            ),
          ),
          size: const Size(820, 700),
          overrides: [
            sourceProvider(SiteId.v2ex).overrideWithValue(source),
            topicDetailProvider(_topic).overrideWith((ref) async => TopicDetail(
                  site: SiteId.v2ex,
                  id: '1',
                  title: '一个帖子',
                  url: 'https://example.com/t/1',
                  content: '<p>正文</p>',
                  author: const Author(name: 'neo'),
                  createdAt: DateTime(2026, 9, 17),
                )),
            repliesProvider.overrideWith(thread),
          ],
        );

    testWidgets('not for a site that cannot be written to', (tester) async {
      await pumpPane(tester, source: FakeSource(null));
      expect(find.byType(ReplyBox), findsNothing,
          reason: 'a box that cannot send is a promise the app cannot keep');
    });

    testWidgets('and one that can', (tester) async {
      await pumpPane(tester,
          source: FakeSource(null, onReply: (_, t) async => _sent(t)));
      expect(find.byType(ReplyBox), findsOneWidget);
    });

    testWidgets('a reply written here lands at the end of the thread',
        (tester) async {
      String? topicId;
      final container = await pumpPane(tester,
          source: FakeSource(null, onReply: (id, text) async {
            topicId = id;
            return _sent('<p>$text</p>');
          }));

      await tester.enterText(find.byType(TextField), '说得好');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(topicId, '1', reason: 'the thread being read is the one answered');
      final thread = container.read(repliesProvider(_topic)).valueOrNull!;
      expect(thread.all.length, 2);
      expect(thread.all.last.content, contains('说得好'));
      expect(thread.total, 2,
          reason: 'the forum holds one more than it said it did');
      expect(find.byType(ReplyTile), findsNWidgets(2));
    });

    testWidgets('a reply to a thread that never loaded says so', (tester) async {
      // There is nothing on screen to put it in, so the pane is told to ask
      // for the thread again rather than quietly dropping a reply that did go
      // out.
      final container = await pumpPane(tester,
          source: FakeSource(null, onReply: (_, t) async => _sent(t)),
          thread: _NoThread.new);
      expect(container.read(repliesProvider(_topic)).hasError, isTrue);
      expect(
          container
              .read(repliesProvider(_topic).notifier)
              .appendSent(_sent('<p>x</p>')),
          isFalse);
    });
  });
}

void _noop() {}
void _noopRef(TopicRef _) {}
