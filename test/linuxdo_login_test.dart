// linux.do has two gates, one behind the other: Cloudflare's challenge, then
// a sign-in. The card has to say which one is next, and signing out must not
// undo the first one — the challenge is the slow half, and reading the forum
// anonymously still needs it.
import 'package:codora/core/linuxdo_session.dart';
import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/features/settings_page.dart';
import 'package:codora/sources/linuxdo_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// What the browser is holding at each stage, in the order they happen.
const _nothing = '';
const _cleared = 'cf_clearance=abc; _ga=1';
const _loggedIn = 'cf_clearance=abc; _ga=1; _t=zzz; _forum_session=qqq';

Finder linuxdoCard() =>
    find.ancestor(of: find.text('Linux.do'), matching: find.byType(SiteCard));

Finder buttonIn(Type type, String label) => find.descendant(
    of: linuxdoCard(), matching: find.widgetWithText(type, label));

void main() {
  resetBootstrapState();

  group('what the card offers next', () {
    Future<void> open(WidgetTester tester, String cookie) => pumpApp(
          tester,
          const SettingsPage(),
          settings: AppSettings(linuxdoCookie: cookie),
          size: const Size(1136, 640),
        );

    testWidgets('the challenge, when nothing has been earned yet',
        (tester) async {
      await open(tester, _nothing);
      expect(buttonIn(FilledButton, '开始验证'), findsOneWidget);
      expect(buttonIn(OutlinedButton, '退出登录'), findsNothing);
    });

    testWidgets('signing in, once the challenge is behind you', (tester) async {
      await open(tester, _cleared);
      // Not '重新验证': that step is done, and the next thing anyone wants is
      // the one they have not done.
      expect(buttonIn(FilledButton, '登录'), findsOneWidget);
      expect(buttonIn(OutlinedButton, '退出登录'), findsNothing);
    });

    testWidgets('a way back out, once signed in', (tester) async {
      await open(tester, _loggedIn);
      expect(buttonIn(FilledButton, '重新验证'), findsOneWidget);
      expect(buttonIn(OutlinedButton, '退出登录'), findsOneWidget);
    });

    testWidgets('only linux.do is signed in to', (tester) async {
      await open(tester, _loggedIn);
      expect(find.widgetWithText(OutlinedButton, '退出登录'), findsOneWidget);
    });
  });

  group('signing out', () {
    test('drops the session and keeps the clearance', () {
      const before = AppSettings(linuxdoCookie: _loggedIn);
      final after = before.withLinuxdoSignedOut();

      expect(after.linuxdoLoggedIn, isFalse);
      expect(after.linuxdoReady, isTrue,
          reason: 'sitting through the challenge again would be the real cost');
      expect(after.linuxdoCookie, contains('_ga=1'),
          reason: 'only the sign-in is being undone');
      expect(after.linuxdoCookie, isNot(contains('_forum_session')));
    });

    test('leaves a cookie with no session alone', () {
      const s = AppSettings(linuxdoCookie: _cleared);
      expect(s.withLinuxdoSignedOut().linuxdoCookie, _cleared);
    });

    test('survives an empty cookie', () {
      expect(const AppSettings().withLinuxdoSignedOut().linuxdoCookie, isEmpty);
    });

    test('does not mistake a cookie whose name merely ends in _t', () {
      const s = AppSettings(linuxdoCookie: 'cf_clearance=a; visit_t=b; _t=c');
      final after = s.withLinuxdoSignedOut();
      expect(after.linuxdoCookie, contains('visit_t=b'));
      expect(after.linuxdoLoggedIn, isFalse);
    });
  });

  // Everything this site serves is fetched inside a WebView, which sends its
  // own cookie jar. Credentials that only reached settings changed what the
  // app believed without changing what it sent — the card read 已登录 while
  // every request went out anonymous.
  group('who counts as signed in', () {
    test('an anonymous visitor is not mistaken for one', () {
      // Discourse hands `_forum_session` to everybody, signed in or not.
      // Reading it as a sign-in made the login page save and close itself the
      // instant it opened — before anyone could type a thing.
      const anon =
          AppSettings(linuxdoCookie: 'cf_clearance=a; _forum_session=b');
      expect(anon.linuxdoLoggedIn, isFalse);
      expect(anon.linuxdoReady, isTrue);
    });

    test('but it still goes when signing out', () {
      expect(kLinuxdoSessionCookies, contains('_forum_session'),
          reason: 'the server would go on treating it as the same session');
      const s = AppSettings(
          linuxdoCookie: 'cf_clearance=a; _forum_session=b; _t=c');
      expect(s.withLinuxdoSignedOut().linuxdoCookie,
          isNot(contains('_forum_session')));
    });

    test('only the sign-in cookie says so', () {
      expect(
          const AppSettings(linuxdoCookie: 'cf_clearance=a; _t=c')
              .linuxdoLoggedIn,
          isTrue);
    });
  });

  // Discourse rotates the sign-in cookie as the site is used, so the copy
  // kept in settings goes stale on its own. Writing it back over the
  // browser's at every launch — which is what seeding blindly did — signs the
  // reader out after enough restarts, and the app goes on believing all is
  // well because settings still hold a `_t`.
  group('which copy of the credentials wins at launch', () {
    test('the browser, whenever it has a sign-in of its own', () {
      expect(
        believedLinuxDoCookie(
            held: 'cf_clearance=new; _t=rotated', stored: 'cf_clearance=old; _t=stale'),
        'cf_clearance=new; _t=rotated',
      );
    });

    test('and what was stored, when the browser has none', () {
      // A fresh install, a new container, or a sign-in carried in by hand.
      expect(
        believedLinuxDoCookie(held: 'cf_clearance=new', stored: 'cf_clearance=a; _t=c'),
        'cf_clearance=a; _t=c',
      );
    });

    test('an empty browser takes what there is', () {
      expect(believedLinuxDoCookie(held: '', stored: 'cf_clearance=a; _t=c'),
          'cf_clearance=a; _t=c');
    });

    test('and a cookie whose name merely ends in _t is not a sign-in', () {
      expect(
        believedLinuxDoCookie(held: 'visit_t=b', stored: '_t=c'),
        '_t=c',
        reason: 'the browser has nothing to keep',
      );
    });
  });

  group('what gets carried into the browser', () {
    test('every cookie of the sign-in', () {
      final applied = cookiesToApply(_loggedIn);
      expect(applied.map((c) => c.$1), containsAll(['_t', '_forum_session']));
      expect(applied, contains(('_t', 'zzz')));
    });

    test('never the clearance, which belongs to the browser that earned it',
        () {
      expect(cookiesToApply(_loggedIn).map((c) => c.$1),
          isNot(contains('cf_clearance')),
          reason: 'one copied from elsewhere is worse than the real one');
    });

    test('a value with an = in it survives whole', () {
      // Session cookies are base64 often enough for this to matter.
      expect(cookiesToApply('_t=YWJj==; x=1'), contains(('_t', 'YWJj==')));
    });

    test('junk between the semicolons is skipped, not guessed at', () {
      expect(cookiesToApply('cf_clearance=a; ; nonsense; =novalue; _t=b'),
          [('_t', 'b')]);
    });

    test('nothing to carry from an empty header', () {
      expect(cookiesToApply(''), isEmpty);
    });
  });

  group('how the source reads those cookies', () {
    SiteAccess accessFor(String cookie) =>
        LinuxDoSource(cookie: cookie, userAgent: kDesktopUserAgent).access;

    test('blocked until the challenge is passed', () {
      expect(accessFor(_nothing).level, AccessLevel.blocked);
    });

    test('limited while anonymous — readable, but not everything', () {
      expect(accessFor(_cleared).level, AccessLevel.limited);
    });

    test('full once signed in', () {
      expect(accessFor(_loggedIn).level, AccessLevel.full);
    });
  });
}
