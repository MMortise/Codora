// Liking a post on linux.do: what the forum says about one, what the heart
// does when it is pressed, and what the thread remembers afterwards.
//
// The payloads are the shapes Discourse sends — a summary line per kind of
// action, with the count left out entirely when it is zero.
import 'dart:async';

import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/features/providers.dart';
import 'package:codora/features/topic_detail.dart';
import 'package:codora/sources/linuxdo_source.dart';
import 'package:codora/widgets/like_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _topic = TopicRef(SiteId.v2ex, '1');

Map _post(List<Map<String, Object?>> actions) => {
      'id': 42,
      'username': 'someone',
      'cooked': '<p>说得好</p>',
      'post_number': 3,
      'actions_summary': actions,
    };

/// A thread of one reply, which is what the heart is pressed on.
class _OneReply extends RepliesNotifier {
  @override
  Future<RepliesState> build(TopicRef arg) async => const RepliesState(
        items: [
          Reply(
            id: '7',
            content: '<p>先来的回复</p>',
            floor: 2,
            likeCount: 4,
            canLike: true,
          ),
        ],
        total: 1,
      );
}

void main() {
  resetBootstrapState();

  group('what the forum says about a like', () {
    test('nobody has, and this reader may', () {
      final like = LinuxDoSource.parseLike(_post([
        {'id': 2, 'can_act': true},
      ]));
      expect(like.count, 0, reason: 'a count of zero is left out entirely');
      expect(like.liked, isFalse);
      expect(like.canLike, isTrue);
      expect(like.open, isTrue);
    });

    test('this reader has, and can still take it back', () {
      final like = LinuxDoSource.parseLike(_post([
        {'id': 2, 'count': 3, 'acted': true, 'can_undo': true},
      ]));
      expect(like.count, 3);
      expect(like.liked, isTrue);
      expect(like.canUnlike, isTrue);
      expect(like.open, isTrue);
    });

    test('the window to take it back has closed', () {
      final like = LinuxDoSource.parseLike(_post([
        {'id': 2, 'count': 3, 'acted': true},
      ]));
      expect(like.liked, isTrue);
      expect(like.open, isFalse, reason: 'nothing left to press');
    });

    test('their own post: it can be counted but not liked', () {
      final like = LinuxDoSource.parseLike(_post([
        {'id': 2, 'count': 9},
      ]));
      expect(like.count, 9);
      expect(like.canLike, isFalse);
      expect(like.open, isFalse);
    });

    test('the other things a post can be done to are not likes', () {
      // 8 is the flag. Reading the first line of the summary would have made
      // every post look liked by whoever could report it.
      final like = LinuxDoSource.parseLike(_post([
        {'id': 8, 'count': 1, 'acted': true, 'can_act': true},
        {'id': 2, 'count': 5, 'can_act': true},
      ]));
      expect(like.count, 5);
      expect(like.liked, isFalse);
    });

    test('a post that says nothing offers nothing', () {
      // Discourse leaves the line out when the count is zero and this reader
      // may not act — their own post. A heart there would be an invitation to
      // a 403; where they may act, the line is there and says so.
      final like = LinuxDoSource.parseLike(_post(const []));
      expect(like.count, 0);
      expect(like.open, isFalse);
    });

    test('but a post whose last like was taken back still offers one', () {
      final like = LinuxDoSource.parseLike(_post([
        {'id': 2, 'can_act': true},
      ]));
      expect(like.count, 0);
      expect(like.open, isTrue);
    });

    test('a reply carries it out of the thread', () {
      final r = LinuxDoSource.parsePost(_post([
        {'id': 2, 'count': 3, 'acted': true, 'can_undo': true},
      ]));
      expect(r.likeCount, 3);
      expect(r.liked, isTrue);
      expect(r.canUnlike, isTrue);
    });
  });

  group('whether there is a heart to press at all', () {
    test('not while anonymous', () {
      expect(
          LinuxDoSource(
                  cookie: 'cf_clearance=a; _forum_session=b',
                  userAgent: kDesktopUserAgent)
              .like,
          isNull);
    });

    test('once signed in', () {
      expect(
          LinuxDoSource(cookie: 'cf_clearance=a; _t=c', userAgent: kDesktopUserAgent)
              .like,
          isNotNull);
    });
  });

  group('the heart', () {
    Future<void> pumpHeart(
      WidgetTester tester,
      LikeState state,
      Future<LikeState> Function(bool) onLike,
    ) =>
        pumpApp(tester, LikeButton(state: state, onLike: onLike),
            size: const Size(400, 200));

    testWidgets('fills the moment it is pressed, not when the forum answers',
        (tester) async {
      // A like is small and immediately reversible; a heart that waits on a
      // round trip before it fills reads as a broken one.
      final answered = Completer<LikeState>();
      bool? asked;
      await pumpHeart(tester, const LikeState(count: 4, canLike: true),
          (like) {
        asked = like;
        return answered.future;
      });

      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pump();

      expect(asked, isTrue);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.text('5 赞'), findsOneWidget, reason: 'one more, at once');

      answered.complete(const LikeState(count: 12, liked: true, canUnlike: true));
      await tester.pumpAndSettle();
      expect(find.text('12 赞'), findsOneWidget,
          reason: 'and then the number the forum actually holds');
    });

    testWidgets('pressing a filled one takes the like back', (tester) async {
      bool? asked;
      await pumpHeart(
        tester,
        const LikeState(count: 4, liked: true, canUnlike: true),
        (like) async {
          asked = like;
          return const LikeState(count: 3, canLike: true);
        },
      );

      await tester.tap(find.byIcon(Icons.favorite_rounded));
      await tester.pumpAndSettle();
      expect(asked, isFalse);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.text('3 赞'), findsOneWidget);
    });

    testWidgets('a refusal turns it back and says why', (tester) async {
      // Held open on purpose: the hopeful state is only there between the
      // press and the answer, and a callback that throws at once would have
      // been back before the first frame.
      final answered = Completer<LikeState>();
      await pumpHeart(tester, const LikeState(count: 4, canLike: true),
          (_) => answered.future);

      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pump();
      expect(find.text('5 赞'), findsOneWidget, reason: 'it went in hopeful');

      answered.completeError(Exception('你今天的点赞用完了'));
      await tester.pumpAndSettle();
      expect(find.text('4 赞'), findsOneWidget, reason: 'and came back');
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.text('你今天的点赞用完了'), findsOneWidget);
    });

    testWidgets('their own post counts its likes and refuses the pointer',
        (tester) async {
      await pumpHeart(tester, const LikeState(count: 9), (_) async {
        throw StateError('should not be asked');
      });
      expect(find.text('9 赞'), findsOneWidget);
      expect(find.byType(MouseRegion).evaluate().isEmpty, isFalse);
      await tester.tap(find.text('9 赞'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'nothing happened');
    });

    testWidgets('nothing to show and nothing to do leaves no room at all',
        (tester) async {
      await pumpHeart(tester, const LikeState(count: 0), (_) async {
        throw StateError('should not be asked');
      });
      expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
      expect(find.textContaining('赞'), findsNothing);
    });

    testWidgets('a thread with something newer to say wins', (tester) async {
      // A tile scrolled out of sight is rebuilt from the list; what the list
      // says then is the truth, not what was pressed here earlier.
      await pumpApp(
        tester,
        _Rebuildable(
          first: const LikeState(count: 4, canLike: true),
          second: const LikeState(count: 40, liked: true, canUnlike: true),
        ),
        size: const Size(400, 200),
      );
      expect(find.text('4 赞'), findsOneWidget);

      await tester.tap(find.text('换一份'));
      await tester.pumpAndSettle();
      expect(find.text('40 赞'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });
  });

  group('in the reading pane', () {
    Future<ProviderContainer> pumpPane(
      WidgetTester tester, {
      required FakeSource source,
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
                  postId: '100',
                  likeCount: 2,
                  canLike: true,
                )),
            repliesProvider.overrideWith(_OneReply.new),
          ],
        );

    testWidgets('a site with no likes to give shows no heart', (tester) async {
      await pumpPane(tester, source: FakeSource(null));
      expect(find.byType(LikeButton), findsNothing);
      expect(find.text('4 赞'), findsOneWidget,
          reason: 'the count is still worth reading');
    });

    testWidgets('a like on a reply is written back into the thread',
        (tester) async {
      // So that scrolling it out of sight and back does not empty the heart.
      String? liked;
      final container = await pumpPane(tester,
          source: FakeSource(null, onLike: (postId, {required like}) async {
            liked = postId;
            return const LikeState(count: 5, liked: true, canUnlike: true);
          }));

      await tester.tap(find.descendant(
          of: find.byType(ReplyTile),
          matching: find.byIcon(Icons.favorite_border_rounded)));
      await tester.pumpAndSettle();

      expect(liked, '7', reason: 'the reply that was pressed, by its post id');
      final thread = container.read(repliesProvider(_topic)).valueOrNull!;
      expect(thread.items.single.likeCount, 5);
      expect(thread.items.single.liked, isTrue);
      expect(thread.items.single.canUnlike, isTrue);
    });

    testWidgets('and the post the topic opens with can be liked too',
        (tester) async {
      String? liked;
      await pumpPane(tester,
          source: FakeSource(null, onLike: (postId, {required like}) async {
            liked = postId;
            return const LikeState(count: 3, liked: true, canUnlike: true);
          }));

      // The opening post wears its like as one of the pills over the body.
      final opening = find.descendant(
          of: find.byType(PostHeader), matching: find.byType(LikeButton));
      expect(opening, findsOneWidget);
      await tester.tap(find.descendant(
          of: opening, matching: find.byIcon(Icons.favorite_border_rounded)));
      await tester.pumpAndSettle();

      expect(liked, '100', reason: 'the post, not the topic');
      expect(find.text('3 赞'), findsOneWidget);
    });
  });
}

/// Draws a heart from one state, then from another — what a rebuilt list does.
class _Rebuildable extends StatefulWidget {
  const _Rebuildable({required this.first, required this.second});

  final LikeState first;
  final LikeState second;

  @override
  State<_Rebuildable> createState() => _RebuildableState();
}

class _RebuildableState extends State<_Rebuildable> {
  bool _later = false;

  @override
  Widget build(BuildContext context) => Column(children: [
        LikeButton(
          state: _later ? widget.second : widget.first,
          onLike: (_) async => widget.first,
        ),
        TextButton(
            onPressed: () => setState(() => _later = true),
            child: const Text('换一份')),
      ]);
}

void _noop() {}
void _noopRef(TopicRef _) {}
