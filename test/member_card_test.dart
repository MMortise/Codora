// The rail's profile card. Two things decide what it can say: what V2EX's
// v2 API hands back for the reader, and the fact that it has no read state of
// its own — the inbox comes back whole every time, so "unread" is a mark this
// app keeps and the card has to be honest about not having one yet.
import 'package:codora/app_theme.dart';
import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/features/member_card.dart';
import 'package:codora/features/providers.dart';
import 'package:codora/sources/v2ex_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Trimmed to the fields the card reads, in the shapes V2EX sends them —
/// note the ids and timestamps arriving as strings.
const _profile = {
  'success': true,
  'result': {
    'id': 298083,
    'username': 'wxVIP',
    'url': 'https://www.v2ex.com/u/wxVIP',
    'tagline': '勤勤恳恳小开发。',
    'bio': '',
    'avatar_normal': '//cdn.v2ex.com/avatar/beb0/298083_normal.png',
    'avatar_large': '//cdn.v2ex.com/avatar/beb0/298083_large.png',
    'created': 1520489134,
    'pro': 0,
  },
};

Map<String, Object?> _inbox(List<int> ids, {int total = 535}) => {
      'success': true,
      'message': 'Notifications 1-${ids.length}/$total',
      'result': [
        for (final id in ids)
          {
            'id': '$id',
            'created': '1789367033',
            'text': '<a href="/member/someone"><strong>someone</strong></a> '
                '在回复 <a href="/t/1">某个主题</a> 时提到了你',
          },
      ],
    };

Member parse(List<int> ids, {int total = 535}) =>
    V2exSource.parseMember(_profile, _inbox(ids, total: total));

void main() {
  resetBootstrapState();

  group('what V2EX hands back', () {
    test('becomes a profile the card can draw', () {
      final m = parse([9, 8, 7]);
      expect(m.name, 'wxVIP');
      expect(m.tagline, '勤勤恳恳小开发。');
      expect(m.number, 298083);
      expect(m.joinedAt?.year, 2018);
      expect(m.badge, isNull, reason: 'this account is not PRO');
      // The page serves protocol-relative avatars; an Image widget cannot
      // open one.
      expect(m.avatarUrl, startsWith('https://'));
    });

    test('falls back to the longer bio when the one-liner is blank', () {
      final profile = {
        'result': {..._profile['result']! as Map, 'tagline': '  ', 'bio': '写点东西'}
      };
      expect(V2exSource.parseMember(profile, _inbox(const [])).tagline, '写点东西');
    });

    test('leaves the tagline off when neither is filled in', () {
      final profile = {
        'result': {..._profile['result']! as Map, 'tagline': '', 'bio': ''}
      };
      expect(V2exSource.parseMember(profile, _inbox(const [])).tagline, isNull);
    });

    test('reads the inbox size out of the only line that states it', () {
      expect(parse([9, 8], total: 535).notificationTotal, 535);
    });

    test('flattens a notification to the one line the card has room for', () {
      expect(parse([9]).notifications.single.text,
          'someone 在回复 某个主题 时提到了你');
    });

    test('is offered only when there is a token to ask with', () {
      expect(V2exSource().member, isNull);
      expect(V2exSource(token: 'abc').member, isNotNull);
    });

    test('gives up long before the feed would, and says which end went quiet',
        () {
      // A hover card cannot spend the client's 15s connect and 30s read: by
      // then the pointer has moved on and all it showed was a spinner.
      expect(V2exSource.memberDeadline, lessThan(const Duration(seconds: 10)));

      final direct = V2exSource(token: 'abc').slowMemberError();
      expect(direct.message, contains('V2EX'));
      expect(direct.hint, contains('代理'), reason: 'suggests setting one');

      final proxied =
          V2exSource(token: 'abc', proxy: '10.0.0.1:8080').slowMemberError();
      expect(proxied.message, contains('代理'),
          reason: 'blames the proxy, not the site behind it');
      expect(proxied.recovery, AuthRecovery.settings);
    });
  });

  group('unread, against a mark this app keeps', () {
    test('counts only what arrived after it', () {
      expect(parse([30, 20, 10]).unreadSince(20), 1);
      expect(parse([30, 20, 10]).unreadSince(5), 3);
      expect(parse([30, 20, 10]).unreadSince(30), 0);
    });

    test('saturates, because only one page is ever fetched', () {
      final m = parse([30, 20, 10]);
      expect(m.saturated(m.unreadSince(5)), isTrue, reason: 'all three are new');
      expect(m.saturated(m.unreadSince(20)), isFalse);
    });

    test('an empty inbox is not saturated at zero', () {
      final m = parse(const []);
      expect(m.saturated(m.unreadSince(0)), isFalse);
      expect(m.newestNotification, 0);
    });

    test('the mark to store is the newest id, whatever order they came in', () {
      expect(parse([10, 30, 20]).newestNotification, 30);
    });
  });

  group('the mark itself', () {
    test('is V2EX\'s alone; the other sites read as never opened', () {
      const s = AppSettings(v2exSeenNotification: 42);
      expect(s.seenNotification(SiteId.v2ex), 42);
      expect(s.seenNotification(SiteId.linuxdo), 0);
      expect(s.withNotificationsSeen(SiteId.linuxdo, 99), same(s));
    });

    test('survives a restart', () async {
      await const AppSettings(v2exSeenNotification: 28385606).save();
      expect((await AppSettings.load()).v2exSeenNotification, 28385606);
    });
  });

  group('the card', () {
    Future<ProviderContainer> show(WidgetTester tester, Member member,
        {AppSettings settings = const AppSettings()}) async {
      AppSettings.bootstrap = settings;
      // Standing in for the site rather than the provider, so the card is
      // tested through the same notifier the app runs.
      final container = ProviderContainer(overrides: [
        sourceProvider(SiteId.v2ex)
            .overrideWithValue(FakeSource(() async => member)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: MemberCard(site: SiteId.v2ex))),
        ),
      ));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('says 消息 and the total before the list has been opened',
        (tester) async {
      final c = await show(tester, parse([30, 20, 10]));
      expect(find.text('消息'), findsOneWidget);
      expect(find.text('未读消息'), findsNothing);
      // Not "3 unread" — a decade of history is not news.
      expect(find.text('535'), findsOneWidget);
      await disposeApp(tester, c);
    });

    testWidgets('switches to 未读消息 once there is a mark to count against',
        (tester) async {
      final c = await show(tester, parse([30, 20, 10]),
          settings: const AppSettings(v2exSeenNotification: 20));
      expect(find.text('未读消息'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      await disposeApp(tester, c);
    });

    testWidgets('marks a full page as more than it can count', (tester) async {
      final c = await show(tester, parse([30, 20, 10]),
          settings: const AppSettings(v2exSeenNotification: 5));
      expect(find.text('3+'), findsOneWidget);
      await disposeApp(tester, c);
    });

    testWidgets('lines its sections up, clickable or not', (tester) async {
      // The inbox block reaches past the card's inset so its hover wash has
      // room; the text inside it still has to sit on the same edge as the
      // lines above and below, which is the part that is easy to lose.
      final c = await show(tester, parse([30, 20, 10]));
      double left(Finder f) => tester.getTopLeft(f).dx;
      final edge = left(find.text('勤勤恳恳小开发。'));
      expect(left(find.textContaining('提到了你')), edge);
      expect(left(find.textContaining('金币')), edge);
      await disposeApp(tester, c);
    });

    testWidgets('lays the level counters out two to a row', (tester) async {
      // Six of these down one side of a card this narrow would be taller than
      // everything above them put together.
      final c = await show(
        tester,
        Member(
          name: 'someone',
          badge: 'LV2',
          stats: const [
            MemberStat('访问天数', '9', target: '15', met: false),
            MemberStat('浏览话题', '2.1k'),
            MemberStat('已读帖子', '1.3w'),
          ],
          progressUrl: Uri.parse('https://connect.linux.do/'),
        ),
      );

      expect(find.text('等级进度'), findsOneWidget);
      expect(find.text('LV2'), findsWidgets);
      expect(tester.getTopLeft(find.text('访问天数')).dy,
          tester.getTopLeft(find.text('浏览话题')).dy,
          reason: 'the first two share a line');
      expect(tester.getTopLeft(find.text('已读帖子')).dy,
          greaterThan(tester.getTopLeft(find.text('访问天数')).dy),
          reason: 'and the third starts the next one');
      await disposeApp(tester, c);
    });

    testWidgets('marks the counter that is short of the bar', (tester) async {
      final c = await show(
        tester,
        const Member(
          name: 'someone',
          stats: [
            MemberStat('访问天数', '9', target: '15', met: false),
            MemberStat('送出的赞', '40'),
          ],
        ),
      );

      expect(find.text(' / 15'), findsOneWidget,
          reason: 'a fixed bar is worth showing');
      expect(tester.widget<Text>(find.text('9')).style?.color,
          Palette.dark.badge, reason: 'short of it is the thing to notice');
      expect(tester.widget<Text>(find.text('40')).style?.color,
          Palette.dark.ink);
      await disposeApp(tester, c);
    });

    testWidgets('a site with nothing to say about levels gets no block',
        (tester) async {
      final c = await show(tester, parse([30]));
      expect(find.text('等级进度'), findsNothing);
      await disposeApp(tester, c);
    });

    testWidgets('shows who the reader is, and what a token cannot reach',
        (tester) async {
      final c = await show(tester, parse([30]));
      expect(find.text('wxVIP'), findsOneWidget);
      expect(find.text('勤勤恳恳小开发。'), findsOneWidget);
      expect(find.text('第 298083 号会员 · 2018 年加入'), findsOneWidget);
      expect(find.textContaining('金币'), findsOneWidget);
      await disposeApp(tester, c);
    });
  });
}
