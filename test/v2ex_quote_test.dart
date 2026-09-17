// V2EX has no reply threading. Readers write it by hand — `@someone`, `#12`,
// or both at the start of a reply — so those prefixes are lifted out and shown
// as a quote rather than being read as the first words of the sentence.
import 'package:codora/core/models.dart';
import 'package:codora/sources/v2ex_source.dart';
import 'package:flutter_test/flutter_test.dart';

const live = bool.fromEnvironment('LIVE');

/// Runs the parser over a handmade thread, so the rules can be pinned down
/// without depending on what people happen to have posted today.
Future<List<Reply>> parse(List<String> renderedBodies) async {
  // The parser is reached through fetchReplies, so the thread is expressed the
  // way the API returns it.
  return V2exSource.parseRepliesForTest([
    for (var i = 0; i < renderedBodies.length; i++)
      {
        'id': '$i',
        'content_rendered': renderedBodies[i],
        'member': {'username': 'user$i'},
        'created': 1700000000 + i,
      }
  ]);
}

String mention(String name) => '@<a href="/member/$name">$name</a>';

void main() {
  group('parsing rules', () {
    test('a plain reply keeps its text and has no quote', () async {
      final replies = await parse(['就是一段普通回复']);
      expect(replies.single.quote, isNull);
      expect(replies.single.content, '就是一段普通回复');
    });

    test('a mention becomes a quote and leaves the sentence', () async {
      final replies = await parse(['第一条', '${mention("user0")} 我同意']);
      final second = replies[1];
      expect(second.quote?.author, 'user0');
      expect(second.content, '我同意',
          reason: 'the mention must not be read as the first word');
    });

    test('a floor reference points at that reply', () async {
      final replies = await parse(['第一条', '第二条', '#1 说得对']);
      expect(replies[2].quote?.floor, 1);
      expect(replies[2].content, '说得对');
    });

    test('a mention and a floor together', () async {
      final replies =
          await parse(['第一条', '${mention("user0")} #1 两个都有']);
      expect(replies[1].quote?.author, 'user0');
      expect(replies[1].quote?.floor, 1);
      expect(replies[1].content, '两个都有');
    });

    test('the quote carries a line of what it answers', () async {
      final replies = await parse(['原始观点在这里', '${mention("user0")} 回应']);
      expect(replies[1].quote?.excerpt, contains('原始观点'));
    });

    test('a number that is not a floor is left in the text', () async {
      // Nothing earlier is numbered 114, so this is just how the reply opens.
      final replies = await parse(['第一条', '#114 这是型号不是楼层']);
      expect(replies[1].quote, isNull);
      expect(replies[1].content, '#114 这是型号不是楼层');
    });

    test('a reply cannot quote something written later', () async {
      final replies = await parse(['#2 指向后面的楼层', '第二条']);
      expect(replies[0].quote, isNull);
      expect(replies[0].content, startsWith('#2'));
    });

    test('a mention resolves to that author\'s latest earlier reply',
        () async {
      final replies = await parse([
        '${mention("zzz")} 开头',
        '第二条',
        '第三条',
        '${mention("user1")} 回给第二条',
      ]);
      expect(replies[3].quote?.author, 'user1');
      expect(replies[3].quote?.floor, 2);
    });

    test('several mentions in a row are all consumed', () async {
      final replies =
          await parse(['甲', '乙', '${mention("user0")} ${mention("user1")} 都看看']);
      expect(replies[2].quote, isNotNull);
      expect(replies[2].content, '都看看');
    });

    test('a mention in the middle of a sentence is left alone', () async {
      final replies =
          await parse(['甲', '我觉得 ${mention("user0")} 说得对']);
      expect(replies[1].quote, isNull,
          reason: 'only a leading reference is a reply marker');
      expect(replies[1].content, contains('我觉得'));
    });
  });

  group('against live replies', () {
    test('quotes are recovered and stripped from the body', () async {
      final src = V2exSource();
      final hot = await src.fetchTopics(
          const Section(id: 'hot', title: '最热'));
      final busy = hot.items.firstWhere((t) => (t.replyCount ?? 0) > 40);
      final replies = await src.fetchReplies(busy.id);

      expect(replies.items.length, greaterThan(40));

      final quoted = replies.items.where((r) => r.quote != null).toList();
      expect(quoted, isNotEmpty,
          reason: 'a busy thread should contain replies to other replies');

      for (final reply in quoted) {
        final quote = reply.quote!;
        expect(quote.isEmpty, isFalse);

        // The reference must be gone from the body, not merely detected.
        expect(reply.content.trimLeft(), isNot(startsWith('@')),
            reason: 'reply #${reply.floor}: ${reply.content}');
        expect(RegExp(r'^\s*#\d').hasMatch(reply.content), isFalse,
            reason: 'reply #${reply.floor}: ${reply.content}');

        if (quote.floor != null) {
          expect(quote.floor, greaterThan(0));
          expect(quote.floor, lessThan(reply.floor! + 1),
              reason: 'a reply can only answer an earlier one');
        }
      }

      // Ordinary replies are untouched.
      final plain = replies.items.where((r) => r.quote == null);
      expect(plain, isNotEmpty);
    });
  }, skip: live ? false : 'set --dart-define=LIVE=true');
}
