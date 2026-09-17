// Switching a forum off takes it off the rail and stops it working in the
// background, without throwing away its credentials. The awkward case is the
// site you were last on disappearing: the shell has to land somewhere, and
// settings has to stay reachable even with every forum switched off.
import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/features/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

List<SiteId> visible(ProviderContainer c) => c.read(visibleSiteIdsProvider);

void main() {
  resetBootstrapState();

  group('settings', () {
    test('every site shows until one is switched off', () {
      const s = AppSettings();
      expect(s.shows(SiteId.v2ex), isTrue);
      expect(s.withSiteShown(SiteId.v2ex, false).shows(SiteId.v2ex), isFalse);
      expect(s.withSiteShown(SiteId.v2ex, false).shows(SiteId.juejin), isTrue);
    });

    test('switching one back on leaves the others alone', () {
      const s = AppSettings(hiddenSites: {SiteId.v2ex, SiteId.juejin});
      final next = s.withSiteShown(SiteId.v2ex, true);
      expect(next.shows(SiteId.v2ex), isTrue);
      expect(next.shows(SiteId.juejin), isFalse);
    });

    test('the choice survives a restart', () async {
      await const AppSettings(hiddenSites: {SiteId.linuxdo}).save();
      final loaded = await AppSettings.load();
      expect(loaded.hiddenSites, {SiteId.linuxdo});
    });

    test('a site added in a later version is not hidden by an old list',
        () async {
      SharedPreferences.setMockInitialValues({
        'hiddenSites': ['linuxdo', 'forum-we-have-never-heard-of'],
      });
      final loaded = await AppSettings.load();
      expect(loaded.hiddenSites, {SiteId.linuxdo});
    });

    test('switching a site off keeps what was typed for it', () {
      const s = AppSettings(v2exToken: 'abc', v2exProxy: 'https://p.test/');
      final off = s.withSiteShown(SiteId.v2ex, false);
      expect(off.v2exToken, 'abc');
      expect(off.v2exProxy, 'https://p.test/');
    });
  });

  group('the rail', () {
    test('lists every site by default, in order', () {
      expect(visible(containerWith()), SiteId.values);
    });

    test('drops the ones switched off', () {
      final c = containerWith(const AppSettings(hiddenSites: {SiteId.linuxdo}));
      expect(visible(c), [SiteId.v2ex, SiteId.juejin]);
    });
  });

  group('where the shell lands', () {
    test('on the first site when nothing is hidden', () {
      expect(containerWith().read(currentNavProvider), NavTarget.v2ex);
    });

    test('on the next site along when the default one is hidden', () {
      final c = containerWith(const AppSettings(hiddenSites: {SiteId.v2ex}));
      expect(c.read(currentNavProvider), NavTarget.linuxdo);
    });

    test('on settings when every forum is switched off', () {
      final c = containerWith(AppSettings(hiddenSites: SiteId.values.toSet()));
      expect(visible(c), isEmpty);
      expect(c.read(currentNavProvider), NavTarget.settings);
    });

    test('settings stays where it is whatever is hidden', () {
      final c = containerWith(AppSettings(hiddenSites: SiteId.values.toSet()));
      c.read(navProvider.notifier).state = NavTarget.settings;
      expect(c.read(currentNavProvider), NavTarget.settings);
    });

    test('a site switched off while you are on it hands over to another', () {
      final c = containerWith();
      c.read(navProvider.notifier).state = NavTarget.juejin;
      expect(c.read(currentNavProvider), NavTarget.juejin);

      c.read(settingsProvider.notifier)
          .patch((s) => s.withSiteShown(SiteId.juejin, false));
      expect(c.read(currentNavProvider), NavTarget.v2ex);
    });

    test('switching it back on returns you to it', () {
      final c = containerWith(const AppSettings(hiddenSites: {SiteId.v2ex}));
      expect(c.read(currentNavProvider), NavTarget.linuxdo);

      c.read(settingsProvider.notifier)
          .patch((s) => s.withSiteShown(SiteId.v2ex, true));
      expect(c.read(currentNavProvider), NavTarget.v2ex);
    });
  });
}
