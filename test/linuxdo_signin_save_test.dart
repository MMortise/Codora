// Saving a linux.do sign-in. The page that does it waits on the whole save,
// so anything thrown on the way leaves it spinning: the profile card used to
// be told to read again from inside the settings it is built from, which
// Riverpod treats as a cycle and refuses — in a debug build, by throwing
// from the last line of the save, after everything had been kept.
//
// Whether Riverpod sees the cycle depends on timing. The moment settings
// change, the site built from them is marked for rebuilding and its link to
// them is dropped; it comes back when the site is rebuilt, which in the app
// is the next frame. Saving takes long enough for several frames — the
// Keychain alone is tens of milliseconds — so by the end of it the link is
// back and the cycle is there to be found. The test draws those frames.
import 'dart:async';

import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/features/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  resetBootstrapState();

  /// A container wired the way the app is: the card reads through the site,
  /// and the site is built from settings. Without that last link there is no
  /// cycle to find.
  ({ProviderContainer c, List<String> handedOver, FakeSource site}) app(
      {Future<void>? browserTakes}) {
    final handedOver = <String>[];
    final site = FakeSource(
      () async => const Member(name: 'someone'),
      id: SiteId.linuxdo,
    );
    final c = containerWith(const AppSettings(), [
      sourceProvider(SiteId.linuxdo).overrideWith((ref) {
        ref.watch(settingsProvider.select((s) => s.linuxdoCookie));
        return site;
      }),
      // WebKit's cookie store and WebViews do not exist under test.
      linuxdoHandoverProvider.overrideWithValue((cookie) async {
        await browserTakes;
        handedOver.add(cookie);
      }),
    ]);
    return (c: c, handedOver: handedOver, site: site);
  }

  testWidgets('a new sign-in is saved all the way through', (tester) async {
    final browser = Completer<void>();
    final (:c, :handedOver, site: _) = app(browserTakes: browser.future);
    // The card, held open the way the rail holds it.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: Consumer(builder: (_, ref, _) {
        ref.watch(memberProvider(SiteId.linuxdo));
        return const SizedBox();
      }),
    ));
    await tester.pumpAndSettle();

    Object? thrown;
    final saving = c
        .read(settingsProvider.notifier)
        .patch((s) => s.copyWith(
            linuxdoCookie: 'cf_clearance=a; _t=b',
            linuxdoUserAgent: kDesktopUserAgent))
        .catchError((Object e) => thrown = e);
    // The app goes on drawing while the browser takes the cookies.
    await tester.pump();
    await tester.pump();
    browser.complete();
    await saving;

    expect(thrown, isNull,
        reason: 'the sign-in page waits on this; a throw leaves it spinning');
    expect(c.read(settingsProvider).linuxdoLoggedIn, isTrue);
    expect(handedOver, ['cf_clearance=a; _t=b'],
        reason: 'the browser the requests run in got the new credentials');
    await tester.pumpWidget(const SizedBox());
  });

  test('and the card reads again once the browser has them', () async {
    // The change itself sets off a read, through a browser that does not
    // have the credentials yet; the one that counts comes after the handover.
    final (:c, :handedOver, :site) = app();
    c.listen(memberProvider(SiteId.linuxdo), (_, _) {});
    await c.read(memberProvider(SiteId.linuxdo).future);
    final before = site.calls;

    final saving = c.read(settingsProvider.notifier).patch(
        (s) => s.copyWith(linuxdoCookie: 'cf_clearance=a; _t=b'));
    await saving;
    await c.read(memberProvider(SiteId.linuxdo).future);

    expect(handedOver, hasLength(1));
    expect(site.calls, greaterThan(before));
    final countAtHandover = c.read(linuxdoHandoversProvider);
    expect(countAtHandover, 1);
  });

  test('a change that is not linux.do hands nothing over', () async {
    final (:c, :handedOver, site: _) = app();
    await c.read(settingsProvider.notifier)
        .patch((s) => s.copyWith(themeMode: 'dark'));
    expect(handedOver, isEmpty);
    expect(c.read(linuxdoHandoversProvider), 0);
  });
}
