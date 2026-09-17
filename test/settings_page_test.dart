// Settings is two tabs: the forums, and everything that is about the app
// rather than a site. Each forum card carries the switch that puts it on the
// rail, and V2EX alone carries the proxy its traffic can be sent through.
import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/features/providers.dart';
import 'package:codora/features/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// The content column of the default window, which is what this page gets.
const paneSize = Size(1136, 640);

late ProviderContainer container;

Future<void> openSettings(WidgetTester tester,
    {AppSettings settings = const AppSettings()}) async {
  container = await pumpApp(tester, const SettingsPage(),
      settings: settings, size: paneSize);
}

Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Finder cardFor(String siteName) =>
    find.ancestor(of: find.text(siteName), matching: find.byType(SiteCard));

/// The switch in a card's header: the one putting the site on the rail.
Finder railSwitch(String siteName) =>
    find.descendant(of: cardFor(siteName), matching: find.byType(Switch)).first;

/// V2EX's card carries a second switch, at the foot of its proxy block.
Finder imageSwitch() =>
    find.descendant(of: cardFor('V2EX'), matching: find.byType(Switch)).last;

/// The save button belonging to one field, rather than any of the others on
/// the same card.
Finder saveFor(String label) => find.descendant(
      of: find
          .ancestor(
              of: find.widgetWithText(TextField, label),
              matching: find.byType(Row))
          .first,
      matching: find.byType(FilledButton),
    );

Future<void> tapAt(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  resetBootstrapState();

  testWidgets('opens on the forums, one card per site', (tester) async {
    await openSettings(tester);
    expect(find.byType(SiteCard), findsNWidgets(SiteId.values.length));
    for (final name in ['V2EX', 'Linux.do', '掘金']) {
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('the general tab holds the theme and the read log',
      (tester) async {
    await openSettings(tester);
    expect(find.text('主题'), findsNothing);

    await tapTab(tester, '常规');
    expect(find.byType(SiteCard), findsNothing);
    expect(find.text('主题'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('阅读记录'), findsOneWidget);
    expect(find.text('清除阅读记录'), findsOneWidget);

    await tapTab(tester, '论坛');
    expect(find.byType(SiteCard), findsNWidgets(SiteId.values.length));
  });

  testWidgets('each site has a switch, reflecting whether it is shown',
      (tester) async {
    await openSettings(
        tester, settings: const AppSettings(hiddenSites: {SiteId.linuxdo}));
    bool shown(String site) => tester.widget<Switch>(railSwitch(site)).value;
    expect(shown('V2EX'), isTrue);
    expect(shown('Linux.do'), isFalse);
    expect(shown('掘金'), isTrue);
  });

  testWidgets('flipping a switch takes the site off the rail', (tester) async {
    await openSettings(tester);
    expect(container.read(settingsProvider).shows(SiteId.juejin), isTrue);

    await tapAt(tester, railSwitch('掘金'));

    expect(container.read(settingsProvider).shows(SiteId.juejin), isFalse);
    expect(container.read(visibleSiteIdsProvider),
        isNot(contains(SiteId.juejin)));
  });

  testWidgets('expanding 手动填写 does not cut the label off', (tester) async {
    // A label only floats up onto the border once the field holds something,
    // which is exactly when it can be clipped.
    await openSettings(tester,
        settings: const AppSettings(linuxdoCookie: 'cf_clearance=abc123'));
    await tapAt(tester, find.text('手动填写'));

    // A floating label straddles its field's top border, so part of it sits
    // above the field's own box. The disclosure clips its body to animate
    // open, and the label used to land on the wrong side of that edge.
    final label = find.text('Cookie（需包含 cf_clearance）');
    expect(label, findsOneWidget);
    final clip = find.descendant(
        of: find.byType(ExpansionTile), matching: find.byType(ClipRect));
    expect(tester.getRect(label).top,
        greaterThanOrEqualTo(tester.getRect(clip.first).top),
        reason: 'the whole label has to be inside what the disclosure shows');
  });

  testWidgets('an address that cannot be used says so', (tester) async {
    // Silently carrying on direct would look identical to a working proxy
    // right up until V2EX fails to load.
    await openSettings(tester,
        settings: const AppSettings(v2exProxy: 'not a proxy'));
    expect(find.textContaining('这个地址用不了'), findsOneWidget);
    expect(tester.widget<Switch>(imageSwitch()).onChanged, isNull);

    await openSettings(tester,
        settings: const AppSettings(v2exProxy: '127.0.0.1:7890'));
    expect(find.textContaining('这个地址用不了'), findsNothing);
  });

  testWidgets('only V2EX offers a proxy', (tester) async {
    await openSettings(tester);
    expect(find.text('代理'), findsOneWidget);
    expect(find.text('代理地址'), findsOneWidget);
    expect(
        tester
            .widget<SiteCard>(find.ancestor(
                of: find.text('代理'), matching: find.byType(SiteCard)))
            .source
            .id,
        SiteId.v2ex);
  });

  testWidgets('the image switch has nothing to offer without an address',
      (tester) async {
    await openSettings(tester);
    expect(find.text('图片也走代理'), findsOneWidget);
    expect(tester.widget<Switch>(imageSwitch()).onChanged, isNull);
  });

  testWidgets('the image switch comes alive once an address is set',
      (tester) async {
    await openSettings(tester,
        settings: const AppSettings(
            v2exProxy: '127.0.0.1:7890', v2exProxyImages: true));
    final s = tester.widget<Switch>(imageSwitch());
    expect(s.onChanged, isNotNull);
    expect(s.value, isTrue);
  });

  testWidgets('an address typed into the proxy field is saved', (tester) async {
    await openSettings(tester);
    final field = find.widgetWithText(TextField, '代理地址');
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, '  127.0.0.1:7890  ');

    await tapAt(tester, saveFor('代理地址'));

    expect(container.read(settingsProvider).v2exProxy, '127.0.0.1:7890');

    // Saving an address is enough: the pictures follow it without a second
    // trip, and the switch is there to opt back out.
    final images = tester.widget<Switch>(imageSwitch());
    expect(images.onChanged, isNotNull);
    expect(images.value, isTrue);
  });
}
