// The box at the foot of a thread: when it is offered at all, what it does
// with what is written in it, and what happens when the forum says no.
import 'dart:async';

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
        items: [
          Reply(
              id: '1',
              content: '<p>先来的回复</p>',
              floor: 2,
              author: Author(name: 'someone')),
        ],
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

    testWidgets('what was written stays, and stays legible, while it goes',
        (tester) async {
      // It was never actually cleared, but a disabled field is painted at 38%
      // opacity, and on this canvas that reads as the box having emptied
      // itself the moment 发送 was pressed.
      await pumpBox(tester, (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.enterText(find.byType(TextField), '说得好');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pump();

      final painted = tester.widget<EditableText>(find.byType(EditableText));
      expect(painted.controller.text, '说得好');
      expect(painted.style.color?.a, 1.0,
          reason: 'faded out is how it looked emptied');
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue,
          reason: 'read-only, so it cannot change under the send');

      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
          isEmpty, reason: 'and emptied only now, once the forum has it');
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

  group('answering one reply rather than the thread', () {
    Future<void> pumpBox(
      WidgetTester tester, {
      ReplyTarget? to,
      VoidCallback? onCancel,
    }) =>
        pumpApp(
            tester,
            ReplyBox(onSend: (_) async {}, to: to, onCancelTarget: onCancel),
            size: const Size(700, 400));

    testWidgets('nothing is said when the thread itself is the answer',
        (tester) async {
      await pumpBox(tester);
      expect(find.textContaining('回复 '), findsNothing);
    });

    testWidgets('who is being answered stands over the box', (tester) async {
      await pumpBox(tester,
          to: const ReplyTarget(postId: '7', floor: 3, author: 'someone'));
      expect(find.text('回复 someone #3'), findsOneWidget);
    });

    testWidgets('a post with nobody on it is still somewhere to write',
        (tester) async {
      // A thread whose first post has no name is not a thread nobody can be
      // answered in.
      await pumpBox(tester, to: const ReplyTarget(postId: '7'));
      expect(find.text('回复 楼主'), findsOneWidget);
    });

    testWidgets('and it can be taken back', (tester) async {
      var cancelled = 0;
      await pumpBox(tester,
          to: const ReplyTarget(postId: '7', floor: 3, author: 'someone'),
          onCancel: () => cancelled++);
      await tester.tap(find.byTooltip('改回复整个帖子'));
      await tester.pumpAndSettle();
      expect(cancelled, 1, reason: 'the pane owns it, so the pane clears it');
    });
  });

  group('a picture in a reply', () {
    Future<void> pumpBox(
      WidgetTester tester,
      Future<String?> Function(PictureSource)? onAttach, {
      Future<void> Function(String)? onSend,
    }) =>
        pumpApp(
            tester,
            ReplyBox(onSend: onSend ?? (_) async {}, onAttach: onAttach),
            size: const Size(700, 400));

    Finder pictureButton() => find.byTooltip(RegExp('^插入图片'));

    testWidgets('not offered by a site that takes none', (tester) async {
      await pumpBox(tester, null);
      expect(pictureButton(), findsNothing,
          reason: 'a button that cannot upload is a promise nothing keeps');
    });

    testWidgets('what the forum answers is written in at the cursor',
        (tester) async {
      // Where the cursor was, not at the end: someone who wrote a paragraph,
      // went back up and asked for a picture meant it there.
      await pumpBox(tester, (_) async => '![a.png|60x40](upload://abc.png)');
      await tester.enterText(find.byType(TextField), '先写一句');
      final field =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      field.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();

      await tester.tap(pictureButton());
      await tester.pumpAndSettle();

      expect(field.text, '先写\n![a.png|60x40](upload://abc.png)\n一句');
      expect(field.selection.baseOffset,
          '先写\n![a.png|60x40](upload://abc.png)\n'.length,
          reason: 'the cursor carries on after it');
    });

    testWidgets('into an empty box it is the whole of it', (tester) async {
      await pumpBox(tester, (_) async => '![a.png](upload://abc.png)');
      await tester.tap(pictureButton());
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '![a.png](upload://abc.png)',
          reason: 'no blank line in front of the first thing written');
    });

    testWidgets('choosing none leaves what was written alone', (tester) async {
      await pumpBox(tester, (_) async => null);
      await tester.enterText(find.byType(TextField), '说得好');
      await tester.pump();
      await tester.tap(pictureButton());
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '说得好');
    });

    testWidgets('a refusal is the forum\'s own sentence, and nothing is written',
        (tester) async {
      await pumpBox(tester, (_) async => throw Exception('图片太大了'));
      await tester.enterText(find.byType(TextField), '说得好');
      await tester.pump();
      await tester.tap(pictureButton());
      await tester.pumpAndSettle();

      expect(find.text('图片太大了'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '说得好');
    });

    testWidgets('nothing goes while a picture is still on its way',
        (tester) async {
      // Held open on purpose: sending now would send a reply with a hole
      // where the picture was going to be.
      final answered = Completer<String?>();
      var sent = 0;
      await pumpBox(tester, (_) => answered.future,
          onSend: (_) async => sent++);
      await tester.enterText(find.byType(TextField), '说得好');
      await tester.pump();
      await tester.tap(pictureButton());
      await tester.pump();

      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);
      await tester.tap(sendButton(), warnIfMissed: false);
      // Pumped rather than settled: the spinner in the button's place is an
      // animation that never ends, and settling waits for one that does.
      await tester.pump();
      expect(sent, 0);

      answered.complete('![a.png](upload://abc.png)');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNotNull,
          reason: 'and goes again once the picture has landed');
    });
  });

  group('pasting into the box', () {
    /// Stands in for the clipboard's words. Null for a clipboard holding
    /// something that is not text — a screenshot, which is the whole point.
    void clipboardHolds(WidgetTester tester, String? text) {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return text == null ? null : <String, dynamic>{'text': text};
        }
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    }

    /// Control rather than the command key: the binding for the platform a
    /// widget test says it is on. The box takes either.
    Future<void> paste(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    Future<TextEditingController> pumpBox(
      WidgetTester tester, {
      Future<String?> Function(PictureSource)? onAttach,
    }) async {
      await pumpApp(tester, ReplyBox(onSend: (_) async {}, onAttach: onAttach),
          size: const Size(700, 400));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      return tester.widget<TextField>(find.byType(TextField)).controller!;
    }

    testWidgets('a picture on the clipboard goes to the forum', (tester) async {
      clipboardHolds(tester, null);
      PictureSource? from;
      final field = await pumpBox(tester, onAttach: (source) async {
        from = source;
        return '![clipboard.png|800x600](upload://abc.png)';
      });

      await paste(tester);

      expect(from, PictureSource.pasted);
      expect(field.text, '![clipboard.png|800x600](upload://abc.png)');
    });

    testWidgets('words on it are still just pasted', (tester) async {
      // A link copied out of a browser is on the clipboard as text *and* as
      // an address AppKit would gladly fetch and call a picture. Pasting a
      // link should paste the link.
      clipboardHolds(tester, 'https://linux.do/t/topic/1');
      var asked = 0;
      final field = await pumpBox(tester, onAttach: (_) async {
        asked++;
        return '![clipboard.png](upload://abc.png)';
      });

      await paste(tester);

      expect(field.text, 'https://linux.do/t/topic/1');
      expect(asked, 0, reason: 'nothing was uploaded');
    });

    testWidgets('and they land where the cursor was', (tester) async {
      clipboardHolds(tester, '很好');
      final field = await pumpBox(tester, onAttach: (_) async => null);
      await tester.enterText(find.byType(TextField), '说得');
      field.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();

      await paste(tester);
      expect(field.text, '说很好得',
          reason: 'no line of its own for words, unlike a picture');
    });

    testWidgets('a site that takes no pictures pastes as it always did',
        (tester) async {
      // Nothing is taken over there, so this is the field's own paste.
      clipboardHolds(tester, '说得好');
      final field = await pumpBox(tester);
      await paste(tester);
      expect(field.text, '说得好');
    });

    testWidgets('an empty clipboard writes nothing and says nothing',
        (tester) async {
      clipboardHolds(tester, null);
      final field = await pumpBox(tester, onAttach: (_) async => null);
      await paste(tester);
      expect(field.text, isEmpty);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
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
          source: FakeSource(null, onReply: (_, t, {to}) async => _sent(t)));
      expect(find.byType(ReplyBox), findsOneWidget);
    });

    testWidgets('a reply written here lands at the end of the thread',
        (tester) async {
      String? topicId;
      final container = await pumpPane(tester,
          source: FakeSource(null, onReply: (id, text, {to}) async {
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

    testWidgets('a reply aimed at one post is sent to that post',
        (tester) async {
      ReplyTarget? aimed;
      await pumpPane(tester,
          source: FakeSource(null, onReply: (id, text, {to}) async {
            aimed = to;
            return _sent('<p>$text</p>');
          }));

      await tester.tap(find.byTooltip('回复 TA'));
      await tester.pumpAndSettle();
      expect(find.text('回复 someone #2'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '同意');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(aimed?.postId, '1');
      expect(aimed?.floor, 2, reason: 'the floor is what Discourse threads by');
      expect(find.text('回复 someone #2'), findsNothing,
          reason: 'it went, so the box is answering the thread again');
    });

    testWidgets('no such button where the thread cannot be answered',
        (tester) async {
      await pumpPane(tester, source: FakeSource(null));
      expect(find.byTooltip('回复 TA'), findsNothing);
    });

    testWidgets('a picture button only where the site takes one',
        (tester) async {
      await pumpPane(tester,
          source: FakeSource(null, onReply: (_, t, {to}) async => _sent(t)));
      expect(find.byTooltip(RegExp('^插入图片')), findsNothing);

      await pumpPane(tester,
          source: FakeSource(null,
              onReply: (_, t, {to}) async => _sent(t),
              onUpload: (name, bytes) async => '![$name](upload://a.png)'));
      expect(find.byTooltip(RegExp('^插入图片')), findsOneWidget);
    });

    testWidgets('a reply to a thread that never loaded says so', (tester) async {
      // There is nothing on screen to put it in, so the pane is told to ask
      // for the thread again rather than quietly dropping a reply that did go
      // out.
      final container = await pumpPane(tester,
          source: FakeSource(null, onReply: (_, t, {to}) async => _sent(t)),
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
