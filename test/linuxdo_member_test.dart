// The rail's profile card for linux.do. Discourse says far more about a
// reader than V2EX does, and — unlike V2EX — it counts its own unread, so the
// card here shows the forum's number rather than a mark this app keeps.
//
// The payloads below are trimmed from what linux.do actually answered, so the
// field names and shapes are the real ones rather than what the docs suggest.
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
      // V2EX carries a note about what a token cannot see. Here there is
      // nothing missing, so there is nothing to explain.
      expect(LinuxDoSource.parseMember(_me).note, isNull);
    });
  });
}
