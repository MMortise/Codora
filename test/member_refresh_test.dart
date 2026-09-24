// When the profile is read, and how often. It is loaded as the app comes up
// rather than when a pointer first asks, and it re-reads itself on a clock —
// so the card is already right when it opens instead of being one request
// behind whoever opened it.
import 'dart:async';

import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/features/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _member = Member(name: 'wxVIP');

void main() {
  resetBootstrapState();

  /// What the rail does: hold the profiles open for as long as it is on
  /// screen. Nothing here touches the card.
  Future<ProviderContainer> openApp(
    WidgetTester tester,
    List<FakeSource> sites,
  ) async {
    final container = ProviderContainer(overrides: [
      for (final site in sites) sourceProvider(site.id).overrideWithValue(site),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(builder: (_, ref, _) {
          ref.watch(loadedMembersProvider);
          return const SizedBox.shrink();
        }),
      ),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('a profile is read as the app comes up, with no hover',
      (tester) async {
    final v2ex = FakeSource(() async => _member);
    final container = await openApp(tester, [v2ex]);

    expect(v2ex.calls, 1, reason: 'nobody has pointed at anything yet');
    expect(container.read(memberProvider(SiteId.v2ex)).valueOrNull, _member);
    await disposeApp(tester, container);
  });

  testWidgets('a site that cannot say who you are is not asked',
      (tester) async {
    final v2ex = FakeSource(null);
    final container = await openApp(tester, [v2ex]);

    expect(v2ex.calls, 0);
    expect(container.read(loadedMembersProvider), isEmpty);
    await disposeApp(tester, container);
  });

  testWidgets('it re-reads itself on the hour', (tester) async {
    // Announcing new notices asks more often; see the next test.
    AppSettings.bootstrap = const AppSettings(quietSites: {SiteId.v2ex});
    final v2ex = FakeSource(() async => _member);
    final container = await openApp(tester, [v2ex]);
    expect(v2ex.calls, 1);

    await tester.pump(memberFreshFor - const Duration(minutes: 1));
    expect(v2ex.calls, 1, reason: 'an hour has not passed yet');

    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(v2ex.calls, 2, reason: 'the hour is up');
    await disposeApp(tester, container);
  });

  testWidgets('a site announcing its notices is read every ten minutes',
      (tester) async {
    final v2ex = FakeSource(() async => _member);
    final container = await openApp(tester, [v2ex]);
    expect(v2ex.calls, 1);

    await tester.pump(memberAnnounceEvery - const Duration(minutes: 1));
    expect(v2ex.calls, 1);

    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(v2ex.calls, 2);
    await disposeApp(tester, container);
  });

  testWidgets('a failure is retried long before the hour', (tester) async {
    var attempt = 0;
    final v2ex = FakeSource(() async {
      if (++attempt == 1) throw Exception('代理没把个人信息带回来');
      return _member;
    });
    final container = await openApp(tester, [v2ex]);
    expect(container.read(memberProvider(SiteId.v2ex)).hasError, isTrue);

    await tester.pump(memberRetryAfter + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(v2ex.calls, 2, reason: 'a bad minute should not cost an hour');
    expect(container.read(memberProvider(SiteId.v2ex)).valueOrNull, _member);
    await disposeApp(tester, container);
  });

  testWidgets('a site taken off the rail stops being asked about',
      (tester) async {
    final v2ex = FakeSource(() async => _member);
    final container = await openApp(tester, [v2ex]);
    expect(v2ex.calls, 1);

    await container
        .read(settingsProvider.notifier)
        .patch((s) => s.withSiteShown(SiteId.v2ex, false));
    await tester.pumpAndSettle();

    await tester.pump(memberFreshFor + const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(v2ex.calls, 1, reason: 'a hidden site is not polled in the corner');
    await disposeApp(tester, container);
  });

  testWidgets('a read overtaken by a newer one does not set its clock',
      (tester) async {
    // The timer was armed from the fetch's own continuation, which runs
    // whether or not that read is still the current one. A slow read landing
    // after a newer one had already failed would replace the one-minute
    // retry with its own hour — leaving the card wrong for an hour because
    // the answer that arrived last was the one nobody was waiting for.
    final slow = Completer<Member>();
    var attempt = 0;
    final v2ex = FakeSource(() async {
      if (++attempt == 1) return slow.future;
      throw Exception('读不到');
    });
    final container = await openApp(tester, [v2ex]);
    expect(v2ex.calls, 1, reason: 'still in flight');

    // A second read starts while the first is still out, and fails fast.
    container.invalidate(memberProvider(SiteId.v2ex));
    await tester.pumpAndSettle();
    expect(container.read(memberProvider(SiteId.v2ex)).hasError, isTrue);

    // Now the first one finally answers, to nobody.
    slow.complete(_member);
    await tester.pumpAndSettle();

    await tester.pump(memberRetryAfter + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(v2ex.calls, 3,
        reason: 'the failure it is actually showing is what sets the clock');
    await disposeApp(tester, container);
  });

  testWidgets('the profile already on screen survives a refresh',
      (tester) async {
    final second = Completer<Member>();
    var attempt = 0;
    final v2ex = FakeSource(() async {
      if (++attempt == 1) return _member;
      return second.future;
    });
    final container = await openApp(tester, [v2ex]);

    await tester.pump(memberFreshFor + const Duration(seconds: 1));
    await tester.pump();

    // Mid-refresh: the old answer is still there to draw, which is what keeps
    // the card from flashing a spinner every hour.
    final state = container.read(memberProvider(SiteId.v2ex));
    expect(state.isLoading, isTrue);
    expect(state.valueOrNull, _member);

    second.complete(const Member(name: 'wxVIP', tagline: '换了签名'));
    await tester.pumpAndSettle();
    expect(container.read(memberProvider(SiteId.v2ex)).valueOrNull?.tagline,
        '换了签名');
    await disposeApp(tester, container);
  });
}
