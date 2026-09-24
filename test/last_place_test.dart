// The app opens where the reader left it: the same site, the same board on
// each, the window where it stood. Each of those can have gone away since —
// a site switched off, a board the forum dropped, the display the window was
// on unplugged — and then it has to land somewhere sensible instead.
import 'dart:ui';

import 'package:codora/core/last_place.dart';
import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/core/window_place.dart';
import 'package:codora/features/providers.dart';
import 'package:codora/features/shell.dart';
import 'package:codora/features/topic_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

/// A site with two boards and nothing on either.
class _TwoBoards extends FakeSource {
  _TwoBoards() : super(null);

  @override
  Future<List<Section>> sections() async => const [
        Section(id: 'tech', title: '技术'),
        Section(id: 'jobs', title: '酷工作'),
      ];

  @override
  Future<PageResult<TopicSummary>> fetchTopics(Section s,
          {String? cursor}) async =>
      const PageResult(items: []);
}

void main() {
  resetBootstrapState();

  group('what is stored', () {
    test('each part comes back after a restart', () async {
      await LastPlace.rememberSite(SiteId.juejin);
      await LastPlace.rememberSection(SiteId.v2ex, 'jobs');
      await LastPlace.rememberSection(SiteId.juejin, 'backend');
      await LastPlace.rememberWindow(const Rect.fromLTWH(40, 60, 1300, 800));

      final loaded = await LastPlace.load();
      expect(loaded.site, SiteId.juejin);
      expect(loaded.sections,
          {SiteId.v2ex: 'jobs', SiteId.juejin: 'backend'});
      expect(loaded.window, const Rect.fromLTWH(40, 60, 1300, 800));
    });

    test('a first launch remembers nothing', () async {
      final loaded = await LastPlace.load();
      expect(loaded.site, isNull);
      expect(loaded.sections, isEmpty);
      expect(loaded.window, isNull);
    });

    test('a site from another version, or a mangled frame, is ignored',
        () async {
      SharedPreferences.setMockInitialValues({
        'lastSite': 'forum-we-have-never-heard-of',
        'windowBounds': ['10', 'NaN', 'wide', '600'],
      });
      final loaded = await LastPlace.load();
      expect(loaded.site, isNull);
      expect(loaded.window, isNull);
    });
  });

  group('the site', () {
    test('opens on the one last used', () {
      LastPlace.bootstrap = const LastPlace(site: SiteId.juejin);
      expect(containerWith().read(currentNavProvider), NavTarget.juejin);
    });

    test('falls back to the first on the rail if that one is switched off',
        () {
      LastPlace.bootstrap = const LastPlace(site: SiteId.v2ex);
      final c = containerWith(const AppSettings(hiddenSites: {SiteId.v2ex}));
      expect(c.read(currentNavProvider), NavTarget.linuxdo);
    });

    test('is written down as the reader moves, but settings never is',
        () async {
      final c = containerWith();
      c.listen(rememberPlaceProvider, (_, _) {});

      c.read(navProvider.notifier).state = NavTarget.linuxdo;
      await pumpEventQueue();
      expect((await LastPlace.load()).site, SiteId.linuxdo);

      c.read(navProvider.notifier).state = NavTarget.settings;
      await pumpEventQueue();
      expect((await LastPlace.load()).site, SiteId.linuxdo);
    });

    test('and so is each board', () async {
      final c = containerWith();
      c.listen(rememberPlaceProvider, (_, _) {});
      c.read(selectedSectionProvider(SiteId.juejin).notifier).state = 'ai';
      await pumpEventQueue();
      expect((await LastPlace.load()).sections, {SiteId.juejin: 'ai'});
    });
  });

  group('the board', () {
    Future<String?> openedOn(WidgetTester tester) async {
      final c = await pumpApp(
        tester,
        const SitePage(site: SiteId.v2ex),
        size: const Size(1200, 800),
        overrides: [sourceProvider(SiteId.v2ex).overrideWithValue(_TwoBoards())],
      );
      final list = tester.widget<TopicListPane>(find.byType(TopicListPane));
      await disposeApp(tester, c);
      return list.sectionId;
    }

    testWidgets('opens on the one last picked', (tester) async {
      LastPlace.bootstrap = const LastPlace(sections: {SiteId.v2ex: 'jobs'});
      expect(await openedOn(tester), 'jobs');
    });

    testWidgets('falls back to the first if the site no longer has it',
        (tester) async {
      LastPlace.bootstrap = const LastPlace(sections: {SiteId.v2ex: 'gone'});
      expect(await openedOn(tester), 'tech');
    });
  });

  group('the window', () {
    const minimum = Size(880, 560);
    const laptop = Rect.fromLTWH(0, 25, 1512, 920);
    const monitorOnRight = Rect.fromLTWH(1512, 0, 2560, 1415);

    test('goes back where it was', () {
      final frame = restorableFrame(const Rect.fromLTWH(1800, 200, 1300, 800),
          [laptop, monitorOnRight],
          minimum: minimum);
      expect(frame.position, const Offset(1800, 200));
      expect(frame.size, const Size(1300, 800));
    });

    test('is centred when the display it was on has gone', () {
      final frame = restorableFrame(const Rect.fromLTWH(1800, 200, 1300, 800),
          [laptop],
          minimum: minimum);
      expect(frame.position, isNull);
      expect(frame.size, const Size(1300, 800));
    });

    test('stays put when only part of it hangs off an edge', () {
      final frame = restorableFrame(const Rect.fromLTWH(1000, 400, 1300, 800),
          [laptop],
          minimum: minimum);
      expect(frame.position, const Offset(1000, 400));
    });

    test('is centred when the top edge it is dragged by is out of reach', () {
      // Only the bottom of the window would be on screen: nothing to grab.
      final frame = restorableFrame(const Rect.fromLTWH(200, -700, 1300, 800),
          [laptop],
          minimum: minimum);
      expect(frame.position, isNull);
    });

    test('is never smaller than the app can lay itself out in', () {
      final frame = restorableFrame(const Rect.fromLTWH(100, 100, 400, 300),
          [laptop],
          minimum: minimum);
      expect(frame.size, minimum);
    });

    test('is centred when the displays cannot be read', () {
      final frame = restorableFrame(const Rect.fromLTWH(100, 100, 1200, 700),
          const [],
          minimum: minimum);
      expect(frame.position, isNull);
    });
  });
}
