// The app's keyboard sits above every page and turns keys into commands for
// the list and the reading pane. What it must never do is take a key that
// someone is typing, or the space bar from a button that has focus.
import 'package:codora/app_theme.dart';
import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/features/keyboard.dart';
import 'package:codora/features/providers.dart';
import 'package:codora/features/topic_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// One long topic and no replies.
class _LongTopic extends FakeSource {
  _LongTopic() : super(null);

  @override
  Future<TopicDetail> fetchTopic(String id) async => TopicDetail(
        site: SiteId.v2ex,
        id: id,
        title: '一篇很长的帖子',
        url: 'https://www.v2ex.com/t/$id',
        content: [for (var i = 0; i < 120; i++) '<p>第 $i 段</p>'].join(),
      );

  @override
  Future<PageResult<Reply>> fetchReplies(String id, {String? cursor}) async =>
      const PageResult(items: []);
}

void main() {
  resetBootstrapState();

  Future<ProviderContainer> pumpKeyboard(WidgetTester tester, Widget home,
      {List<Override> overrides = const []}) async {
    final container = containerWith(const AppSettings(), overrides);
    final navigatorKey = GlobalKey<NavigatorState>();
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        navigatorKey: navigatorKey,
        builder: (_, navigator) =>
            AppKeyboard(navigatorKey: navigatorKey, child: navigator!),
        home: Scaffold(body: home),
      ),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  ListCommand? listCommand(ProviderContainer c) =>
      c.read(listCommandProvider(SiteId.v2ex))?.kind;
  DetailCommand? detailCommand(ProviderContainer c) =>
      c.read(detailCommandProvider(SiteId.v2ex))?.kind;

  group('keys become commands for the site on screen', () {
    testWidgets('J and K move through the list', (tester) async {
      final c = await pumpKeyboard(tester, const SizedBox());
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      expect(listCommand(c), ListCommand.next);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      expect(listCommand(c), ListCommand.previous);
    });

    testWidgets('the same key twice is two commands', (tester) async {
      final c = await pumpKeyboard(tester, const SizedBox());
      final seen = <int>[];
      c.listen(listCommandProvider(SiteId.v2ex),
          (_, next) => seen.add(next!.serial));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      expect(seen, hasLength(2));
    });

    testWidgets('R refreshes the list; shift R reloads the thread',
        (tester) async {
      final c = await pumpKeyboard(tester, const SizedBox());
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      expect(listCommand(c), ListCommand.refresh);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(detailCommand(c), DetailCommand.reload);
    });

    testWidgets('space pages, O opens, C copies', (tester) async {
      final c = await pumpKeyboard(tester, const SizedBox());
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(detailCommand(c), DetailCommand.pageDown);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(detailCommand(c), DetailCommand.pageUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      expect(detailCommand(c), DetailCommand.openInBrowser);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      expect(detailCommand(c), DetailCommand.copyLink);
    });

    testWidgets('g g goes to the top, one g alone does nothing, shift G to '
        'the bottom', (tester) async {
      final c = await pumpKeyboard(tester, const SizedBox());
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      expect(detailCommand(c), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      expect(detailCommand(c), DetailCommand.top);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(detailCommand(c), DetailCommand.bottom);
    });

    testWidgets('two g far apart are not a chord', (tester) async {
      final c = await pumpKeyboard(tester, const SizedBox());
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.runAsync(() => Future<void>.delayed(
          kChordWindow + const Duration(milliseconds: 100)));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      expect(detailCommand(c), isNull);
    });
  });

  group('the modifier keys', () {
    testWidgets('a number goes to that site on the rail', (tester) async {
      final c = await pumpKeyboard(tester, const SizedBox());
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(c.read(currentNavProvider), NavTarget.juejin);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(c.read(currentNavProvider), NavTarget.v2ex);
    });

    testWidgets('a number past the last site does nothing', (tester) async {
      final c = await pumpKeyboard(tester, const SizedBox());
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(c.read(currentNavProvider), NavTarget.v2ex);
    });

    testWidgets('comma opens settings', (tester) async {
      final c = await pumpKeyboard(tester, const SizedBox());
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(c.read(currentNavProvider), NavTarget.settings);
    });

    testWidgets('settings takes no list or thread commands', (tester) async {
      final c = await pumpKeyboard(tester, const SizedBox());
      c.read(navProvider.notifier).state = NavTarget.settings;
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      expect(listCommand(c), isNull);
    });
  });

  group('search', () {
    int asked(ProviderContainer c) => c.read(searchRequestProvider(SiteId.v2ex));

    testWidgets('⌘F asks the site on screen to search', (tester) async {
      final c = await pumpKeyboard(tester, const SizedBox());
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(asked(c), 1);
    });

    testWidgets('and so does /', (tester) async {
      final c = await pumpKeyboard(tester, const SizedBox());
      await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
      expect(asked(c), 1);
    });

    testWidgets('but not from settings', (tester) async {
      final c = await pumpKeyboard(tester, const SizedBox());
      c.read(navProvider.notifier).state = NavTarget.settings;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(asked(c), 0);
    });
  });

  group('what the keyboard leaves alone', () {
    testWidgets('keys typed into a text field stay there', (tester) async {
      final text = TextEditingController();
      addTearDown(text.dispose);
      final c = await pumpKeyboard(tester, TextField(controller: text));
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '');
      for (final key in [
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyJ,
        LogicalKeyboardKey.space,
      ]) {
        await tester.sendKeyEvent(key);
      }
      expect(listCommand(c), isNull);
      expect(detailCommand(c), isNull);
    });

    testWidgets('a focused button keeps its space bar', (tester) async {
      var pressed = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final c = await pumpKeyboard(
          tester,
          TextButton(
              focusNode: focus,
              onPressed: () => pressed++,
              child: const Text('按钮')));
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(pressed, 1);
      expect(detailCommand(c), isNull);
    });
  });

  testWidgets('? shows every shortcut', (tester) async {
    await pumpKeyboard(tester, const SizedBox());
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutSheet), findsOneWidget);
    for (final (_, what) in kShortcuts) {
      expect(find.text(what), findsOneWidget);
    }
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutSheet), findsNothing);

    // The keyboard still answers once the sheet is gone.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.byType(ShortcutSheet), findsOneWidget);
  });

  group('the reading pane', () {
    Future<ProviderContainer> pumpThread(WidgetTester tester) =>
        pumpKeyboard(
          tester,
          TopicDetailView(
            topic: const TopicRef(SiteId.v2ex, '1'),
            canGoBack: false,
            onBack: () {},
            onOpenTopic: (_) {},
          ),
          overrides: [sourceProvider(SiteId.v2ex).overrideWithValue(_LongTopic())],
        );

    double offset(WidgetTester tester) => tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;

    testWidgets('turns a page, and goes to either end', (tester) async {
      await pumpThread(tester);
      expect(offset(tester), 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      final page = offset(tester);
      expect(page, greaterThan(300));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      final bottom = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .maxScrollExtent;
      expect(offset(tester), bottom);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.pumpAndSettle();
      expect(offset(tester), 0);
    });

    testWidgets('copies its link', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpThread(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(copied, 'https://www.v2ex.com/t/1');
      expect(find.text('链接已复制'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });
  });
}
