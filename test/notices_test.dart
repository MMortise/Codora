// New notices are announced by the system, once each, and only while the app
// is not in front; the app's icon carries the unread count. A first read never
// announces the reader's whole history, and a site can be kept quiet.
import 'package:codora/core/models.dart';
import 'package:codora/core/notices.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/features/notify_panel.dart';
import 'package:codora/features/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Member inbox(List<int> ids, {int? unread}) => Member(
      name: 'neo',
      unread: unread,
      notifications: [
        for (final id in ids) Notice(id: id, text: '第 $id 条消息'),
      ],
    );

void main() {
  resetBootstrapState();

  group('counting', () {
    test('a site that counts its own unread is believed', () {
      expect(unreadOf(inbox([3, 2, 1], unread: 7), 0), 7);
    });

    test('one that does not is counted from the mark, once there is one', () {
      expect(unreadOf(inbox([3, 2, 1]), 0), 0,
          reason: 'never opened: not a decade of unread');
      expect(unreadOf(inbox([3, 2, 1]), 1), 2);
    });
  });

  group('what is said', () {
    test('one new notice is quoted', () {
      final a = announcementFor(SiteId.v2ex, inbox([3, 2]), 2)!;
      expect(a.title, 'V2EX 有新消息');
      expect(a.body, '第 3 条消息');
    });

    test('several are counted, and the newest quoted', () {
      final a = announcementFor(SiteId.linuxdo, inbox([2, 5, 4, 3]), 2)!;
      expect(a.title, 'Linux.do 有 3 条新消息');
      expect(a.body, '第 5 条消息');
    });

    test('nothing new is nothing to say', () {
      expect(announcementFor(SiteId.v2ex, inbox([3, 2]), 3), isNull);
    });

    test('marks survive a restart', () async {
      await AnnouncedMarks.empty.withMark(SiteId.v2ex, 42).save(SiteId.v2ex);
      final loaded = await AnnouncedMarks.load();
      expect(loaded.of(SiteId.v2ex), 42);
      expect(loaded.of(SiteId.linuxdo), isNull);
    });
  });

  group('the watcher', () {
    late Member current;
    late FakeOutlet outlet;

    setUp(() {
      current = inbox([3, 2, 1]);
      outlet = NoticeOutlet.instance as FakeOutlet;
    });

    Future<ProviderContainer> openApp(WidgetTester tester,
        {AppSettings settings = const AppSettings(),
        AppLifecycleState state = AppLifecycleState.inactive}) async {
      tester.binding.handleAppLifecycleStateChanged(state);
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      final c = containerWith(settings, [
        sourceProvider(SiteId.v2ex)
            .overrideWithValue(FakeSource(() async => current)),
      ]);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Consumer(builder: (_, ref, _) {
            ref.watch(inboxWatcherProvider);
            return const SizedBox.shrink();
          }),
        ),
      ));
      await tester.pumpAndSettle();
      return c;
    }

    Future<void> reread(WidgetTester tester, ProviderContainer c) async {
      c.invalidate(memberProvider(SiteId.v2ex));
      await tester.pumpAndSettle();
    }

    testWidgets('announces nothing on the first read, only marks it',
        (tester) async {
      final c = await openApp(tester);
      expect(outlet.announced, isEmpty);
      expect(AnnouncedMarks.bootstrap.of(SiteId.v2ex), 3);
      await disposeApp(tester, c);
    });

    testWidgets('announces what arrives after, once', (tester) async {
      final c = await openApp(tester);
      current = inbox([5, 4, 3, 2, 1]);
      await reread(tester, c);
      expect(outlet.announced, [
        (SiteId.v2ex, 'V2EX 有 2 条新消息', '第 5 条消息'),
      ]);
      await reread(tester, c);
      expect(outlet.announced, hasLength(1), reason: 'nothing new since');
      await disposeApp(tester, c);
    });

    testWidgets('picks up after a restart without repeating itself',
        (tester) async {
      AnnouncedMarks.bootstrap = AnnouncedMarks.empty.withMark(SiteId.v2ex, 3);
      current = inbox([4, 3, 2]);
      final c = await openApp(tester);
      expect(outlet.announced.single.$3, '第 4 条消息');
      await disposeApp(tester, c);
    });

    testWidgets('says nothing while the app is in front', (tester) async {
      final c = await openApp(tester, state: AppLifecycleState.resumed);
      current = inbox([5, 4, 3]);
      await reread(tester, c);
      expect(outlet.announced, isEmpty);
      expect(AnnouncedMarks.bootstrap.of(SiteId.v2ex), 5,
          reason: 'seen in the app is seen; it is not announced later');
      await disposeApp(tester, c);
    });

    testWidgets('says nothing for a site kept quiet', (tester) async {
      final c = await openApp(tester,
          settings: const AppSettings(quietSites: {SiteId.v2ex}));
      current = inbox([5, 4, 3], unread: 2);
      await reread(tester, c);
      expect(outlet.announced, isEmpty);
      expect(outlet.badges.last, 0);
      await disposeApp(tester, c);
    });

    testWidgets('puts the unread count on the icon', (tester) async {
      current = inbox([5, 4, 3], unread: 2);
      final c = await openApp(tester);
      expect(outlet.badges.last, 2);
      current = inbox([5, 4, 3], unread: 0);
      await reread(tester, c);
      expect(outlet.badges.last, 0);
      await disposeApp(tester, c);
    });

    testWidgets('recounts when the inbox is opened from the card',
        (tester) async {
      current = inbox([5, 4, 3]);
      final c = await openApp(tester,
          settings: const AppSettings(v2exSeenNotification: 3));
      expect(outlet.badges.last, 2);
      await c.read(settingsProvider.notifier)
          .patch((s) => s.withNotificationsSeen(SiteId.v2ex, 5));
      await tester.pumpAndSettle();
      expect(outlet.badges.last, 0);
      await disposeApp(tester, c);
    });

    testWidgets('pressing an announcement goes to its site', (tester) async {
      final c = await openApp(tester);
      c.read(navProvider.notifier).state = NavTarget.settings;
      outlet.onOpen!(SiteId.v2ex);
      expect(c.read(navProvider), NavTarget.v2ex);
      await disposeApp(tester, c);
    });
  });

  group('the panel', () {
    testWidgets('switches a site off, and says why one cannot be',
        (tester) async {
      final c = await pumpApp(
        tester,
        const SingleChildScrollView(child: NotifyPanel()),
        size: const Size(900, 900),
        overrides: [
          sourceProvider(SiteId.v2ex)
              .overrideWithValue(FakeSource(() async => inbox([1]))),
          sourceProvider(SiteId.linuxdo)
              .overrideWithValue(FakeSource(null, id: SiteId.linuxdo)),
          sourceProvider(SiteId.juejin)
              .overrideWithValue(FakeSource(null, id: SiteId.juejin)),
        ],
      );
      expect(find.text('登录 linux.do 之后才读得到消息'), findsOneWidget);
      expect(find.text('掘金的消息还读不到'), findsOneWidget);
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches.map((s) => s.onChanged != null), [true, false, false]);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(c.read(settingsProvider).announces(SiteId.v2ex), isFalse);
    });

    test('the choice survives a restart', () async {
      await const AppSettings(quietSites: {SiteId.linuxdo}).save();
      final loaded = await AppSettings.load();
      expect(loaded.announces(SiteId.linuxdo), isFalse);
      expect(loaded.announces(SiteId.v2ex), isTrue);
    });
  });
}
