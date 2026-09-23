// Answering a thread on linux.do. Discourse takes the write over the same
// session the reading goes through, and explains a refusal in the body rather
// than in the status — which is the part worth putting in front of anyone.
//
// The payloads below are the shapes Discourse actually sends.
import 'dart:typed_data';

import 'package:codora/core/settings.dart';
import 'package:codora/core/util.dart';
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

/// What `POST /uploads.json` hands back once it has the picture.
const _uploaded = {
  'id': 802414,
  'url': 'https://linux.do/uploads/default/original/4X/a/b/c/d9f.png',
  'original_filename': '截图.png',
  'filesize': 51422,
  'width': 1179,
  'height': 764,
  'short_url': 'upload://mZbvGpQ2s.png',
  'short_path': '/uploads/short-url/mZbvGpQ2s.png',
  'extension': 'png',
};

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

  group('what a reply was written to', () {
    Map answering(int? floor, {String? who, String cooked = '<p>同意</p>'}) => {
          ..._created,
          'cooked': cooked,
          'reply_to_post_number': floor,
          if (who != null) 'reply_to_user': {'username': who},
        };

    test('is carried out of the thread with it', () {
      final r = LinuxDoSource.parsePost(answering(7, who: 'neo'));
      expect(r.quote?.floor, 7);
      expect(r.quote?.author, 'neo');
    });

    test('a reply to the thread itself answers nobody', () {
      expect(LinuxDoSource.parsePost(answering(null)).quote, isNull);
    });

    test('and one that quotes says it once, not twice', () {
      // Whoever pressed 引用 rather than 回复 has the name and the words
      // inside the post already; a line above saying the same would be the
      // second copy of one thought.
      final r = LinuxDoSource.parsePost(answering(7,
          who: 'neo',
          cooked: '<aside class="quote no-group"><blockquote>'
              '<p>原话</p></blockquote></aside><p>同意</p>'));
      expect(r.quote, isNull);
    });
  });

  group('handing over a picture', () {
    test('is offered to someone signed in, and to nobody else', () {
      expect(sourceWith('cf_clearance=a; _forum_session=b').uploadImage, isNull);
      expect(sourceWith('cf_clearance=a; _t=c').uploadImage, isNotNull);
    });

    test('what goes into the box is the short address and the size', () {
      // The `upload://` form rather than the plain URL: the forum resolves it
      // as it renders, so the picture survives the file moving stores. The
      // size, because Discourse draws a picture at whatever the markdown
      // names — and a phone screenshot with none named is drawn at 1179px.
      expect(LinuxDoSource.uploadMarkdown(_uploaded, filename: 'a.png'),
          '![截图.png|1179x764](upload://mZbvGpQ2s.png)');
    });

    test('an install that gives no short address falls back to the URL', () {
      final upload = {..._uploaded}..remove('short_url');
      expect(LinuxDoSource.uploadMarkdown(upload, filename: 'a.png'),
          contains('(https://linux.do/uploads/'));
    });

    test('nothing to point at is worth saying out loud', () {
      // It did go up. Writing `![a.png]()` into someone's reply would not be
      // better than telling them to look.
      expect(
          () => LinuxDoSource.uploadMarkdown(const {}, filename: 'a.png'),
          throwsA(isA<Exception>()));
    });

    test('a file the forum said no size for still gets written in', () {
      final upload = {..._uploaded}
        ..remove('width')
        ..remove('height');
      expect(LinuxDoSource.uploadMarkdown(upload, filename: 'a.png'),
          '![截图.png](upload://mZbvGpQ2s.png)');
    });

    test('and a name with markdown in it cannot break the link', () {
      final upload = {..._uploaded, 'original_filename': 'a[1]|b.png'};
      expect(LinuxDoSource.uploadMarkdown(upload, filename: 'a.png'),
          '![a_1__b.png|1179x764](upload://mZbvGpQ2s.png)');
    });

    test('the name the picker gave stands in where the forum forgot', () {
      final upload = {..._uploaded}..remove('original_filename');
      expect(LinuxDoSource.uploadMarkdown(upload, filename: '本地.png'),
          startsWith('![本地.png|'));
    });

    test('the file is announced as what it is', () {
      // The browser writes a content type onto everything it sends in a form,
      // and a PNG announced as a stream of bytes is one a forum can refuse.
      expect(pictureContentType('截图.PNG'), 'image/png');
      expect(pictureContentType('a.jpeg'), 'image/jpeg');
      expect(pictureContentType('notes'), 'application/octet-stream');
    });

    test('one too big to cross is refused here rather than out there', () async {
      // Not the forum's limit, which is the forum's to state: the bytes reach
      // the page as base64, a third longer again, and a wait that ends in
      // nothing is worse than a sentence.
      final source = sourceWith('cf_clearance=a; _t=c');
      await expectLater(
        source.uploadImage!('big.png', Uint8List(13 * 1024 * 1024)),
        throwsA(predicate((e) => '$e'.contains('太大'))),
      );
    });
  });

  group('when the forum refuses a picture', () {
    test('its own sentence is what gets shown', () {
      expect(
        LinuxDoSource.uploadProblem(refusal(
            422, '{"errors":["文件大小超出限制：最大 4096 KB"]}')),
        '文件大小超出限制：最大 4096 KB',
      );
    });

    test('and a refusal with nothing to say is about the picture', () {
      // Not "这个帖子不在了": a thread is not what was refused.
      expect(LinuxDoSource.uploadProblem(refusal(413, '')), contains('太大'));
      expect(LinuxDoSource.uploadProblem(refusal(422, '')), contains('不接受'));
      expect(LinuxDoSource.uploadProblem(refusal(0, 'TypeError: Load failed')),
          contains('网络'));
    });

    test('a bare 403 is Cloudflare, not the forum', () {
      // The forum says why in the body when it is the one refusing. An empty
      // 403 is the challenge, and that is the one with something to do about
      // it.
      expect(LinuxDoSource.uploadProblem(refusal(403, '')), contains('人机验证'));
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
