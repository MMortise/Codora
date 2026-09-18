// The rail's profile card for linux.do. Discourse says far more about a
// reader than V2EX does, and — unlike V2EX — it counts its own unread, so the
// card here shows the forum's number rather than a mark this app keeps.
//
// The payloads below are trimmed from what linux.do actually answered, so the
// field names and shapes are the real ones rather than what the docs suggest.
import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/sources/linuxdo_source.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = {
  'id': 58550,
  'username': 'someone',
  'name': '某人',
  'avatar_template': '/user_avatar/linux.do/someone/{size}/275691_2.png',
  // Two counts that sound alike and are not. The first is only the part of
  // the unread that is not high priority.
  'unread_notifications': 0,
  'unread_high_priority_notifications': 2,
  'all_unread_notifications_count': 2,
  'admin': false,
  'moderator': false,
  'trust_level': 2,
};

const _profile = {
  'created_at': '2024-11-20T06:06:53.109Z',
  'bio_excerpt': '好人一生平安。',
};

const _notices = [
  {
    'id': 900,
    'notification_type': 25,
    'read': false,
    'created_at': '2026-09-17T12:00:00.000Z',
    'fancy_title': '大家都是用的什么移动套餐？',
    'acting_user_name': '真名',
    'data': {'topic_title': '大家都是用的什么移动套餐？', 'display_username': '回帖的人'},
  },
];

/// What `/u/{name}/summary.json` hands back, trimmed to the counters a level
/// is decided on.
const _summary = {
  'likes_given': 12,
  'likes_received': 45,
  'topics_entered': 2103,
  'posts_read_count': 12840,
  'days_visited': 88,
  'time_read': 129600,
  'topic_count': 3,
  'post_count': 40,
  'bookmark_count': 7,
};

MemberStat statNamed(Member m, String label) =>
    m.stats.firstWhere((s) => s.label == label);

void main() {
  LinuxDoSource sourceWith(String cookie) =>
      LinuxDoSource(cookie: cookie, userAgent: kDesktopUserAgent);

  group('whether there is a card at all', () {
    test('not while anonymous, however far past the challenge', () {
      expect(sourceWith('cf_clearance=a; _forum_session=b').member, isNull,
          reason: 'there is no reader to describe');
    });

    test('once signed in', () {
      expect(sourceWith('cf_clearance=a; _t=c').member, isNotNull);
    });
  });

  group('what Discourse hands back', () {
    test('becomes the same card V2EX gets', () {
      final m = LinuxDoSource.parseMember(_me,
          profile: _profile, notices: _notices);

      expect(m.name, 'someone');
      expect(m.number, 58550, reason: 'the signup number, as on V2EX');
      expect(m.joinedAt?.year, 2024);
      expect(m.url, 'https://linux.do/u/someone');
      expect(m.avatarUrl,
          'https://linux.do/user_avatar/linux.do/someone/144/275691_2.png',
          reason: 'the {size} placeholder has to be filled in');
    });

    test('the bio becomes the line under the name', () {
      final m = LinuxDoSource.parseMember(_me, profile: _profile);
      expect(m.tagline, '好人一生平安。');
    });

    test('and the display name stands in when there is no bio', () {
      final m = LinuxDoSource.parseMember(_me);
      expect(m.tagline, '某人');
    });

    test('trust level is the badge, where V2EX has PRO', () {
      expect(LinuxDoSource.parseMember(_me).badge, 'LV2');
    });

    test('staff outrank a trust level', () {
      expect(
          LinuxDoSource.parseMember({..._me, 'moderator': true}).badge, 'MOD');
      expect(LinuxDoSource.parseMember({..._me, 'admin': true}).badge, 'ADMIN');
    });
  });

  group('the unread count', () {
    test('is the one Discourse puts on its own bell', () {
      // `unread_notifications` reads 0 here while two replies are waiting;
      // taking it would have shown an empty inbox to someone who had mail.
      expect(LinuxDoSource.parseMember(_me).unread, 2);
    });

    test('falls back when a forum does not send that field', () {
      final older = {..._me}..remove('all_unread_notifications_count');
      expect(LinuxDoSource.parseMember(older).unread, 0);
    });

    test('being the site\'s own, the card keeps no mark of its own', () {
      final m = LinuxDoSource.parseMember(_me, notices: _notices);
      expect(m.unread, isNotNull,
          reason: 'which is what tells the card not to count for itself');
    });
  });

  group('a notification line', () {
    test('says who and what', () {
      final m = LinuxDoSource.parseMember(_me, notices: _notices);
      expect(m.notifications.single.text, '回帖的人 · 大家都是用的什么移动套餐？');
      expect(m.notifications.single.createdAt?.year, 2026);
    });

    test('falls back to the topic title when there is no fancy one', () {
      final row = {..._notices.first}..remove('fancy_title');
      final m = LinuxDoSource.parseMember(_me, notices: [row]);
      expect(m.notifications.single.text, contains('移动套餐'));
    });

    test('survives a row with nothing useful in it', () {
      final m = LinuxDoSource.parseMember(_me, notices: [
        {'id': 1, 'data': const {}},
      ]);
      expect(m.notifications.single.text, isEmpty);
    });
  });

  // connect.linux.do reports on these, and it can do so properly: it signs in
  // on its own side and reads the hundred-day windows a member's session
  // never sees. What is reachable from here is the counters themselves.
  group('how far along the reader is', () {
    test('the six counters a level is decided on', () {
      final m = LinuxDoSource.parseMember(_me, summary: _summary);
      expect(m.stats.map((s) => s.label), [
        '访问天数',
        '浏览话题',
        '已读帖子',
        '阅读时长',
        '送出的赞',
        '收到的赞',
      ]);
      expect(statNamed(m, '访问天数').value, '88');
      expect(statNamed(m, '浏览话题').value, '2.1k');
      expect(statNamed(m, '收到的赞').value, '45');
    });

    test('a span of time is read as a span of time', () {
      expect(statNamed(LinuxDoSource.parseMember(_me, summary: _summary),
              '阅读时长').value,
          '36 小时');
      expect(
          statNamed(
                  LinuxDoSource.parseMember(_me,
                      summary: {..._summary, 'time_read': 600}),
                  '阅读时长')
              .value,
          '10 分钟');
      expect(
          statNamed(
                  LinuxDoSource.parseMember(_me,
                      summary: {..._summary, 'time_read': 5400}),
                  '阅读时长')
              .value,
          '1.5 小时');
    });

    test('below 2 级 the bar is shown, because it is a fixed number',
        (() {
      // Discourse decides the first two levels on counters kept over the
      // whole of a reader's time, so these are the real thresholds.
      final m = LinuxDoSource.parseMember(
          {..._me, 'trust_level': 1},
          summary: {..._summary, 'days_visited': 9, 'likes_given': 0});

      expect(statNamed(m, '访问天数').target, '15');
      expect(statNamed(m, '访问天数').met, isFalse, reason: '9 of 15');
      expect(statNamed(m, '送出的赞').target, '1');
      expect(statNamed(m, '送出的赞').met, isFalse);
      expect(statNamed(m, '浏览话题').met, isTrue, reason: '2103 of 20');
    })); 

    test('at 2 级 no bar is invented', () {
      // Every requirement for 3 级 is measured over the last hundred days,
      // and two of them against how busy the site itself has been. Nothing a
      // member can read says either, so a number here would be made up.
      final m = LinuxDoSource.parseMember(_me, summary: _summary);
      expect(m.stats.every((s) => s.target == null), isTrue);
      expect(m.stats.every((s) => s.met), isTrue);
      expect(m.note, contains('100 天'));
      expect(m.progressUrl.toString(), 'https://connect.linux.do/');
    });

    test('and a forum that will not hand the summary over shows none', () {
      final m = LinuxDoSource.parseMember(_me);
      expect(m.stats, isEmpty);
      expect(m.progressUrl, isNull);
      expect(m.note, isNull, reason: 'nothing to explain without the numbers');
    });
  });

  group('when the extras are refused', () {
    test('the card is still built from the session alone', () {
      // Either of the other two requests may be locked down on a given
      // Discourse; a card without a join date beats no card.
      final m = LinuxDoSource.parseMember(_me);
      expect(m.name, 'someone');
      expect(m.joinedAt, isNull);
      expect(m.notifications, isEmpty);
      expect(m.unread, 2);
    });

    test('and says nothing it cannot reach', () {
      // V2EX carries a note about what a token cannot see. With no summary
      // there is nothing to qualify either, so there is nothing to explain.
      expect(LinuxDoSource.parseMember(_me).note, isNull);
    });
  });
}
