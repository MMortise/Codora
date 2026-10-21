// A list being asked for is said on the rail, round the block of the site on
// screen, rather than as a bar across the top of the list — where it covered
// the first title, and where nobody was looking to see which site this was.
import 'dart:async';
import 'dart:typed_data';

import 'package:codora/app_theme.dart';
import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/core/snapshot.dart';
import 'package:codora/features/providers.dart';
import 'package:codora/features/shell.dart';
import 'package:codora/features/topic_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A site whose list answers only when the test says so.
class _HeldSite extends FakeSource {
  _HeldSite() : super(null);

  Completer<void> held = Completer<void>();
  int fetches = 0;

  @override
  Future<List<Section>> sections() async =>
      const [Section(id: 'all', title: '全部')];

  @override
  Future<PageResult<TopicSummary>> fetchTopics(Section s,
      {String? cursor}) async {
    fetches++;
    await held.future;
    return PageResult(items: [
      for (var i = 0; i < 3; i++)
        TopicSummary(
            site: SiteId.v2ex,
            id: '$i',
            title: '帖 $i',
            url: 'https://www.v2ex.com/t/$i'),
    ]);
  }
}

Finder ring() => find.byKey(const ValueKey('rail-busy-ring'));

void main() {
  resetBootstrapState();

  // Made inside each test rather than in setUp: a future born outside the
  // test's fake clock does not answer inside it.
  late _HeldSite site;
  setUp(() => Snapshots.instance = memorySnapshots(<Uri, Uint8List>{}));

  /// The whole shell, with only V2EX on the rail. Not settled: while the
  /// list is on its way there is a spinner, and settling waits for it.
  Future<ProviderContainer> pumpShell(WidgetTester tester) async {
    final c = containerWith(
        const AppSettings(hiddenSites: {SiteId.linuxdo, SiteId.juejin}),
        [sourceProvider(SiteId.v2ex).overrideWithValue(site)]);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const AppShell()),
    ));
    return c;
  }

  /// Pumped rather than settled while the ring turns: it is an animation
  /// that runs for as long as the list is on its way.
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('turns round the site while its list first loads, then stops',
      (tester) async {
    site = _HeldSite();
    await pumpShell(tester);
    await frames(tester);
    expect(site.fetches, 1);
    expect(ring(), findsOneWidget);

    site.held.complete();
    await tester.pumpAndSettle();
    expect(ring(), findsNothing);
    expect(find.text('帖 0'), findsOneWidget);
  });

  testWidgets('and again while it refreshes, with nothing over the list',
      (tester) async {
    site = _HeldSite()..held.complete();
    final c = await pumpShell(tester);
    await tester.pumpAndSettle();
    expect(ring(), findsNothing);

    site.held = Completer<void>();
    unawaited(c.read(feedProvider(const FeedKey(SiteId.v2ex, 'all')).notifier).refresh());
    await frames(tester);
    expect(ring(), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(TopicListPane),
            matching: find.byType(LinearProgressIndicator)),
        findsNothing,
        reason: 'the first title stays uncovered');
    expect(find.text('帖 0'), findsOneWidget,
        reason: 'and the list stays readable meanwhile');

    site.held.complete();
    await tester.pumpAndSettle();
    expect(ring(), findsNothing);
  });

  testWidgets('a site that is not on screen says nothing', (tester) async {
    site = _HeldSite()..held.complete();
    final c = await pumpShell(tester);
    await tester.pumpAndSettle();
    c.read(navProvider.notifier).state = NavTarget.settings;
    await tester.pumpAndSettle();

    site.held = Completer<void>();
    unawaited(c.read(feedProvider(const FeedKey(SiteId.v2ex, 'all')).notifier).refresh());
    await frames(tester);
    expect(ring(), findsNothing);
    site.held.complete();
    await tester.pumpAndSettle();
  });
}
