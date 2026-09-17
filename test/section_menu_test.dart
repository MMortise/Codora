// The board dropdown lists a Chinese name beside the board's own latin slug.
// Spacing them apart pushed the slug to the far edge and left a gulf between
// the two, and the stock menu row height left a lot of air around short names.
import 'package:codora/app_theme.dart';
import 'package:codora/core/models.dart';
import 'package:codora/features/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const boards = <Section>[
  Section(id: 'node:programmer', title: '程序员', subtitle: 'programmer', group: '节点'),
  Section(id: 'node:share', title: '分享发现', subtitle: 'share', group: '节点'),
  Section(id: 'node:qna', title: '问与答', subtitle: 'qna', group: '节点'),
  Section(id: 'node:apple', title: 'Apple', subtitle: 'apple', group: '节点'),
];

List<Section> manyBoards(int count) => [
      for (var i = 0; i < count; i++)
        Section(id: 'n$i', title: '板块$i', subtitle: 'board$i', group: '节点'),
    ];

Future<void> openMenuWith(
  WidgetTester tester,
  List<Section> sections, {
  String? selected,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SectionGroupMenu(
          label: '节点',
          sections: sections,
          selectedId: selected,
          onSelect: (_) {},
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.tap(find.byType(SectionGroupMenu));
  await tester.pumpAndSettle();
}

/// The height the dropdown actually occupies on screen.
double panelHeight(WidgetTester tester) => tester
    .getRect(find.ancestor(
      of: find.byType(MenuItemButton).first,
      matching: find.byType(ConstrainedBox),
    ).first)
    .height;

/// The dropdown's own scroller. Looking downward from a SingleChildScrollView
/// can land on one the menu framework owns, so this looks upward from a row.
ScrollableState scrollerIn(WidgetTester tester) => tester.state<ScrollableState>(
    find.ancestor(
      of: find.byType(MenuItemButton).first,
      matching: find.byType(Scrollable),
    ).first);

/// Finds a board inside the dropdown. The trigger shows the selected board's
/// name too, so a bare text finder matches twice.
Finder boardInMenu(String label) => find.descendant(
      of: find.byType(MenuItemButton),
      matching: find.text(label),
    );

Future<void> openMenu(WidgetTester tester, {String? selected}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SectionGroupMenu(
          label: '节点',
          sections: boards,
          selectedId: selected,
          onSelect: (_) {},
        ),
      ),
    ),
  ));
  await tester.pump();
  // Tapping by type, because the trigger shows the selected board's name
  // rather than the group label once something is selected.
  await tester.tap(find.byType(SectionGroupMenu));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every board is listed with its slug', (tester) async {
    await openMenu(tester);
    for (final board in boards) {
      expect(find.text(board.title), findsOneWidget);
      expect(find.text(board.subtitle!), findsOneWidget);
    }
  });

  testWidgets('rows are compact, not touch-sized', (tester) async {
    await openMenu(tester);
    final row = tester.getRect(find.ancestor(
      of: find.text('程序员'),
      matching: find.byType(MenuItemButton),
    ).first);
    expect(row.height, kMenuRowHeight,
        reason: 'a stock menu row is around 48 and reads as padded');
  });

  testWidgets('a row does not pad the text it holds', (tester) async {
    await openMenu(tester);
    final text = tester.getRect(find.descendant(
      of: find.byType(MenuItemButton),
      matching: find.text('程序员'),
    ));
    final row = tester.getRect(find.ancestor(
      of: find.text('程序员'),
      matching: find.byType(MenuItemButton),
    ).first);
    // Whatever is left over sits half above and half below the line.
    expect((row.height - text.height) / 2, closeTo(10, 0.5),
        reason: 'the agreed breathing room around each board');
  });

  testWidgets('rows sit directly against each other', (tester) async {
    await openMenu(tester);
    final rows = find.byType(MenuItemButton);
    final first = tester.getRect(rows.at(0));
    final second = tester.getRect(rows.at(1));
    expect(second.top - first.bottom, 0,
        reason: 'a gap between rows would double the apparent padding');
  });

  testWidgets('the panel does not add its own top and bottom inset',
      (tester) async {
    await openMenu(tester);
    final rows = find.byType(MenuItemButton);
    final panel = tester.getRect(find.ancestor(
      of: rows.at(0),
      matching: find.byType(Column),
    ).first);
    expect(tester.getRect(rows.at(0)).top - panel.top, lessThanOrEqualTo(1),
        reason: 'the first board should start at the panel edge');
    expect(panel.bottom - tester.getRect(rows.at(boards.length - 1)).bottom,
        lessThanOrEqualTo(1),
        reason: 'and the last should end at it');
  });

  group('opening the menu', () {
    /// Opens without settling, so the transition can be observed part-way.
    Future<void> beginOpening(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SectionGroupMenu(
              label: '节点',
              sections: boards,
              selectedId: null,
              onSelect: (_) {},
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.tap(find.byType(SectionGroupMenu));
      await tester.pump();
    }

    /// Transitions belonging to the dropdown, not to the page route.
    Iterable<T> inPanel<T extends Widget>(WidgetTester tester) =>
        tester.widgetList<T>(find.ancestor(
          of: find.byType(MenuItemButton).first,
          matching: find.byType(T),
        ));

    testWidgets('it fades in rather than appearing', (tester) async {
      await beginOpening(tester);
      await tester.pump(Motion.swap ~/ 2);

      final fades = inPanel<FadeTransition>(tester);
      expect(fades, isNotEmpty);
      expect(fades.any((f) => f.opacity.value > 0 && f.opacity.value < 1),
          isTrue,
          reason: 'mid-transition the panel should be partly transparent');
    });

    testWidgets('it grows from the edge it hangs off', (tester) async {
      await beginOpening(tester);
      await tester.pump(Motion.swap ~/ 2);

      final scales = inPanel<ScaleTransition>(tester);
      expect(scales.any((s) => s.scale.value < 1), isTrue,
          reason: 'it should still be growing');
      expect(scales.first.alignment, Alignment.topCenter,
          reason: 'it hangs below the trigger, so it opens downward');
    });

    testWidgets('and settles fully open', (tester) async {
      await beginOpening(tester);
      await tester.pumpAndSettle();

      for (final fade in inPanel<FadeTransition>(tester)) {
        expect(fade.opacity.value, 1);
      }
      for (final scale in inPanel<ScaleTransition>(tester)) {
        expect(scale.scale.value, 1);
      }
      for (final slide in inPanel<SlideTransition>(tester)) {
        expect(slide.position.value, Offset.zero);
      }
    });

    testWidgets('the boards are readable once it settles', (tester) async {
      await beginOpening(tester);
      await tester.pumpAndSettle();
      expect(find.text('程序员'), findsOneWidget);
      expect(find.text('programmer'), findsOneWidget);
    });
  });

  testWidgets('the slug follows the name instead of hugging the far edge',
      (tester) async {
    await openMenu(tester);
    final name = tester.getRect(find.text('程序员'));
    final slug = tester.getRect(find.text('programmer'));
    final row = tester.getRect(find.ancestor(
      of: find.text('程序员'),
      matching: find.byType(MenuItemButton),
    ).first);

    final gapBetween = slug.left - name.right;
    final gapAfter = row.right - slug.right;
    expect(gapBetween, lessThan(60),
        reason: 'the two used to sit at opposite ends of the row');
    expect(gapAfter, lessThan(30), reason: 'and the slug hugged the edge');
  });

  testWidgets('slugs line up into a column', (tester) async {
    await openMenu(tester);
    // Names differ in length, but a minimum width keeps the slugs aligned
    // without spacing them apart.
    final lefts = ['programmer', 'share', 'qna']
        .map((s) => tester.getRect(find.text(s)).left)
        .toSet();
    expect(lefts.length, 1, reason: 'slugs should share one left edge');
  });

  testWidgets('a name longer than the column still fits', (tester) async {
    await openMenu(tester);
    expect(tester.takeException(), isNull);
    final apple = tester.getRect(find.text('Apple'));
    final slug = tester.getRect(find.text('apple'));
    expect(slug.left, greaterThan(apple.right));
  });

  testWidgets('the selected board is marked by colour, not by an icon slot',
      (tester) async {
    await openMenu(tester, selected: 'node:qna');
    Text inMenu(String label) => tester.widget<Text>(find.descendant(
          of: find.byType(MenuItemButton),
          matching: find.text(label),
        ));
    final selected = inMenu('问与答');
    final other = inMenu('程序员');
    expect(selected.style?.color, Palette.dark.accent);
    expect(other.style?.color, isNot(Palette.dark.accent));
    expect(find.byIcon(Icons.circle), findsNothing,
        reason: 'a leading icon slot would indent every row');
  });

  group('a long board list', () {
    const visible = kMenuVisibleRows;

    testWidgets('shows every board when there are few enough', (tester) async {
      await openMenuWith(tester, manyBoards(6));
      expect(find.byType(MenuItemButton), findsNWidgets(6));
      expect(panelHeight(tester), 6 * kMenuRowHeight,
          reason: 'a short list should not reserve empty space');
      expect(scrollerIn(tester).position.maxScrollExtent, 0,
          reason: 'and should not scroll');
    });

    testWidgets('stops growing at ten', (tester) async {
      await openMenuWith(tester, manyBoards(18));
      expect(panelHeight(tester), visible * kMenuRowHeight);
    });

    testWidgets('exactly ten neither scrolls nor clips', (tester) async {
      await openMenuWith(tester, manyBoards(visible));
      expect(panelHeight(tester), visible * kMenuRowHeight);
      expect(scrollerIn(tester).position.maxScrollExtent, 0);
    });

    testWidgets('the rest are reachable by scrolling', (tester) async {
      await openMenuWith(tester, manyBoards(18));
      final scroller = scrollerIn(tester);
      expect(scroller.position.maxScrollExtent, (18 - visible) * kMenuRowHeight,
          reason: 'everything past the tenth should be scrollable to');

      // Every row is built; the ones past the tenth are simply clipped out of
      // the window, so position is what says whether one can be read.
      final window = tester.getRect(find.ancestor(
        of: find.byType(MenuItemButton).first,
        matching: find.byType(ConstrainedBox),
      ).first);
      expect(tester.getRect(boardInMenu('板块17')).top,
          greaterThan(window.bottom),
          reason: 'below the fold before scrolling');

      scroller.position.jumpTo(scroller.position.maxScrollExtent);
      await tester.pump();
      expect(tester.getRect(boardInMenu('板块17')).bottom,
          lessThanOrEqualTo(window.bottom + 0.5),
          reason: 'and readable after');
    });

    testWidgets('a board picked earlier is scrolled into view on open',
        (tester) async {
      await openMenuWith(tester, manyBoards(18), selected: 'n15');
      // Without this, reopening the menu would show the top of the list and
      // hide the board currently in use.
      expect(boardInMenu('板块15'), findsOneWidget);
      expect(scrollerIn(tester).position.pixels, greaterThan(0));
    });

    testWidgets('a board near the top does not force a scroll',
        (tester) async {
      await openMenuWith(tester, manyBoards(18), selected: 'n1');
      expect(scrollerIn(tester).position.pixels, 0);
      expect(boardInMenu('板块1'), findsOneWidget);
    });
  });
}
