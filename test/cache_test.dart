// The cache panel: what it says is on disk, and what a limit can be set to.
// The bar is the point of it — someone should be able to look at one strip
// and see which of the three is actually costing them room.
import 'package:codora/core/cache_usage.dart';
import 'package:codora/core/disk_cache.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/features/cache_panel.dart';
import 'package:codora/features/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _gb = 1024 * 1024 * 1024;

CacheReport reportOf({
  int images = 0,
  int web = 0,
  int readLog = 0,
  int limit = kDefaultCacheLimit,
  int capacity = 500 * _gb,
}) =>
    CacheReport(
      sizes: {
        CacheKind.images: images,
        CacheKind.web: web,
        CacheKind.readLog: readLog,
      },
      limit: limit,
      capacity: capacity,
    );

/// The bar is private, so it is found by the one public thing it clips with.
final _barType = ClipRRect;

void main() {
  resetBootstrapState();

  group('sizes as people say them', () {
    test('rounds to something readable', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(999), '999 B');
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(10 * _gb), '10 GB');
    });

    test('drops a decimal that says nothing', () {
      // "1.0 GB" is noise where "1 GB" is not.
      expect(formatBytes(_gb), '1 GB');
      expect(formatBytes((_gb * 1.4).round()), '1.4 GB');
    });

    test('no decimals once the number speaks for itself', () {
      expect(formatBytes(512 * _gb), '512 GB');
    });
  });

  group('what a limit can be set to', () {
    test('ends at the disk, whatever the ladder says', () {
      final stops = limitStops(40 * _gb);
      expect(stops.last, 40 * _gb);
      expect(stops.every((s) => s <= 40 * _gb), isTrue,
          reason: 'offering more room than exists would be a lie');
    });

    test('a small disk still offers something', () {
      final stops = limitStops(300 * 1024 * 1024);
      expect(stops, isNotEmpty);
      expect(stops.last, 300 * 1024 * 1024);
    });

    test('the default is one of them on an ordinary disk', () {
      expect(limitStops(500 * _gb), contains(kDefaultCacheLimit));
    });

    test('they only ever go up', () {
      final stops = limitStops(500 * _gb);
      for (var i = 1; i < stops.length; i++) {
        expect(stops[i], greaterThan(stops[i - 1]));
      }
    });
  });

  group('the report', () {
    test('adds the kinds up', () {
      final r = reportOf(images: 3 * _gb, web: _gb, readLog: 1024);
      expect(r.total, 4 * _gb + 1024);
      expect(r.of(CacheKind.images), 3 * _gb);
    });

    test('a kind nobody has used reads as nothing, not as missing', () {
      expect(reportOf().of(CacheKind.web), 0);
    });
  });

  group('the panel', () {
    Future<ProviderContainer> show(
        WidgetTester tester, CacheReport report) async {
      return pumpApp(
        tester,
        const CachePanel(),
        settings: AppSettings(cacheLimit: report.limit),
        size: const Size(700, 600),
        overrides: [cacheReportProvider.overrideWith((_) async => report)],
      );
    }

    testWidgets('names every kind and what it costs', (tester) async {
      await show(tester, reportOf(images: 2 * _gb, web: 300 * 1024 * 1024));

      for (final kind in CacheKind.values) {
        expect(find.text(kind.label), findsOneWidget);
      }
      expect(find.text('2 GB'), findsOneWidget);
      expect(find.text('300 MB'), findsOneWidget);
    });

    /// The painted width of one kind's slice of the bar.
    double sliceOf(WidgetTester tester, CacheKind kind) =>
        tester.getSize(find.byKey(ValueKey(kind))).width;

    testWidgets('the bar is actually drawn', (tester) async {
      // It was not, for a while: a `Flexible` hands its child an upper bound,
      // and a coloured box with nothing inside took that as licence to be
      // nothing at all. The legend looked right while the bar was empty.
      await show(tester, reportOf(images: 5 * _gb, limit: 10 * _gb));
      expect(sliceOf(tester, CacheKind.images), greaterThan(10));
    });

    testWidgets('a kind gets width in proportion to its size', (tester) async {
      await show(tester, reportOf(images: 4 * _gb, web: _gb, limit: 10 * _gb));
      final images = sliceOf(tester, CacheKind.images);
      final web = sliceOf(tester, CacheKind.web);
      expect(images / web, closeTo(4, 0.1));
    });

    testWidgets('and the rest of the bar is the room left', (tester) async {
      // Half the budget used means half the bar coloured, which is the whole
      // reason it is measured against the limit rather than the total.
      await show(tester, reportOf(images: 5 * _gb, limit: 10 * _gb));
      final bar = tester.getSize(find.byType(_barType)).width;
      expect(sliceOf(tester, CacheKind.images), closeTo(bar / 2, 2));
    });

    testWidgets('something tiny still shows up', (tester) async {
      // 48 KB against a 10 GB budget rounds to nothing, and "nothing" is the
      // one thing the bar must not say about something that is there.
      await show(tester, reportOf(images: 5 * _gb, readLog: 48 * 1024));
      expect(sliceOf(tester, CacheKind.readLog), greaterThan(0));
    });

    testWidgets('a full cache does not overflow the bar', (tester) async {
      await show(tester,
          reportOf(images: 9 * _gb, web: _gb, readLog: 32, limit: 10 * _gb));
      final bar = tester.getSize(find.byType(_barType)).width;
      final used = CacheKind.values
          .map((k) => sliceOf(tester, k))
          .fold(0.0, (a, b) => a + b);
      expect(used, lessThanOrEqualTo(bar + 0.5));
    });

    testWidgets('the limit is stored when the thumb is let go, not on the way',
        (tester) async {
      // Every stop passed through would otherwise save the settings, measure
      // the disk all over again, and run a real trim — deleting pictures to
      // fit budgets the reader was only travelling through on the way down.
      final container =
          await show(tester, reportOf(images: _gb, limit: 10 * _gb));
      final slider = find.byType(Slider);

      final thumb = await tester.startGesture(tester.getCenter(slider));
      await thumb.moveBy(const Offset(-200, 0));
      await tester.pump();
      expect(container.read(settingsProvider).cacheLimit, 10 * _gb,
          reason: 'nothing is stored while the thumb is still down');
      expect(find.text('10 GB'), findsNothing,
          reason: 'though what it says follows the thumb');

      await thumb.up();
      await tester.pumpAndSettle();
      expect(container.read(settingsProvider).cacheLimit, lessThan(10 * _gb),
          reason: 'letting go is what commits it');
    });

    testWidgets('a disk with room for only one stop still draws',
        (tester) async {
      // The ladder starts at 256 MB, so a smaller volume leaves a single stop
      // — and a Slider asserts rather than draw with nothing to divide.
      await show(tester,
          reportOf(images: 4 * 1024, capacity: 100 * 1024 * 1024));
      expect(tester.takeException(), isNull);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull,
          reason: 'there is nowhere else to put it');
    });

    testWidgets('leads with the total', (tester) async {
      await show(tester, reportOf(images: _gb, web: _gb));
      expect(find.text('共 2 GB'), findsOneWidget);
    });

    testWidgets('nothing cached leaves nothing to clear', (tester) async {
      await show(tester, reportOf());
      final button =
          tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '清理缓存'));
      expect(button.onPressed, isNull);
    });

    testWidgets('something cached can be cleared', (tester) async {
      await show(tester, reportOf(images: 5 * 1024));
      final button =
          tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '清理缓存'));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('both clears sit together', (tester) async {
      // The narrower one belongs beside the one that takes everything: apart,
      // it read as a different feature rather than a smaller version of it.
      await show(tester, reportOf(images: _gb));
      final whole = find.widgetWithText(OutlinedButton, '清理缓存');
      final history = find.widgetWithText(OutlinedButton, '清除阅读记录');
      expect(whole, findsOneWidget);
      expect(history, findsOneWidget);
      expect(tester.getRect(history).left,
          greaterThan(tester.getRect(whole).right));
      expect(tester.getRect(history).top, tester.getRect(whole).top);
    });

    testWidgets('nothing read leaves nothing to forget', (tester) async {
      await show(tester, reportOf(images: _gb));
      final history = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, '清除阅读记录'));
      expect(history.onPressed, isNull);
    });

    testWidgets('clearing asks first, and says what it costs', (tester) async {
      await show(tester, reportOf(images: 5 * _gb));
      await tester.tap(find.widgetWithText(OutlinedButton, '清理缓存'));
      await tester.pumpAndSettle();

      // What it takes and what it leaves. `clearAllCache` reaches WebKit's
      // caches and nothing else, so promising a sign-out would be a threat it
      // cannot carry out — 退出登录 is the button that means that.
      expect(find.textContaining('人机验证和登录都留着'), findsOneWidget);
      expect(find.textContaining('重新变成未读'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    });

    testWidgets('and does nothing if the answer is no', (tester) async {
      await show(tester, reportOf(images: 5 * _gb));
      await tester.tap(find.widgetWithText(OutlinedButton, '清理缓存'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(find.textContaining('重新变成未读'), findsNothing,
          reason: 'the dialog is gone and nothing was touched');
    });
  });
}
