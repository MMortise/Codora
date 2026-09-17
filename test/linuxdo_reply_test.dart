// Answering a thread on linux.do. Discourse takes the write over the same
// session the reading goes through, and explains a refusal in the body rather
// than in the status — which is the part worth putting in front of anyone.
//
// The payloads below are the shapes Discourse actually sends.
import 'package:codora/core/settings.dart';
import 'package:codora/core/webview_fetcher.dart';
import 'package:codora/sources/linuxdo_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// What `POST /posts` hands back: the post it made of the text.
const _created = {
  'id': 1284003,
  'username': 'someone',
  'name': '某人',
  'avatar_template': '/user_avatar/linux.do/someone/{size}/275691_2.png',
  'created_at': '2026-09-18T03:21:44.123Z',
  'cooked': '<p>说得好，我也这么觉得。</p>',
  'post_number': 42,
  'topic_id': 999,
};

WebViewFetchException refusal(int status, String body) =>
    WebViewFetchException(status, body);

void main() {
  LinuxDoSource sourceWith(String cookie) =>
      LinuxDoSource(cookie: cookie, userAgent: kDesktopUserAgent);

  group('whether there is a box at all', () {
    test('not while anonymous, however far past the challenge', () {
      expect(sourceWith('cf_clearance=a; _forum_session=b').reply, isNull,
          reason: 'there is nothing to send with');
    });

    test('once signed in', () {
      expect(sourceWith('cf_clearance=a; _t=c').reply, isNotNull);
    });
  });

  group('what comes back from sending one', () {
    test('is the reply, ready to sit at the end of the thread', () {
      final r = LinuxDoSource.parsePost(_created);
      expect(r.id, '1284003');
      expect(r.content, '<p>说得好，我也这么觉得。</p>');
      expect(r.floor, 42, reason: 'the post number is the floor');
      expect(r.author?.name, 'someone');
      expect(r.createdAt?.year, 2026);
    });

    test('and carries the avatar the rest of the thread uses', () {
      expect(LinuxDoSource.parsePost(_created).author?.avatarUrl,
          'https://linux.do/user_avatar/linux.do/someone/96/275691_2.png');
    });
  });

  group('when the forum refuses it', () {
    test('its own sentence is what gets shown', () {
      // A status code says nothing about what to do differently; this does.
      expect(
        LinuxDoSource.postProblem(refusal(
            422, '{"action":"create_post","errors":["正文似乎不清晰，是否可以再详细一些？"]}')),
        '正文似乎不清晰，是否可以再详细一些？',
      );
    });

    test('several complaints are joined rather than one being picked', () {
      expect(
        LinuxDoSource.postProblem(
            refusal(422, '{"errors":["标题太短了","正文太短了"]}')),
        '标题太短了；正文太短了',
      );
    });

    test('posting too fast reads as what it is', () {
      expect(
        LinuxDoSource.postProblem(refusal(429,
            '{"errors":["你回复得太快了，请稍后再试。"],"error_type":"rate_limit"}')),
        '你回复得太快了，请稍后再试。',
      );
    });

    test('a body with nothing to say falls back to the status', () {
      expect(LinuxDoSource.postProblem(refusal(500, '{}')), contains('500'));
    });

    test('and one that is not JSON at all does not throw over it', () {
      expect(LinuxDoSource.postProblem(refusal(502, '<html>bad gateway')),
          contains('502'));
    });

    test('the challenge is named, because that one has a fix', () {
      expect(LinuxDoSource.postProblem(refusal(403, 'Just a moment...')),
          contains('人机验证'));
    });

    test('a request that never arrived is not reported as a refusal', () {
      expect(LinuxDoSource.postProblem(refusal(0, 'TypeError: Load failed')),
          contains('网络'));
    });
  });
}
