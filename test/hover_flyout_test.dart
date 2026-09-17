// The hover panel behind the rail's profile card. The awkward part is not
// opening it but keeping it open: the pointer leaves the trigger to reach the
// panel, so a flyout that closed the instant hover ended could never be used.
import 'package:codora/widgets/hover_flyout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Trigger on the left, panel to its right with a gap between them — the
  /// same arrangement the rail uses.
  Future<void> pump(WidgetTester tester, {bool withPanel = true}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: HoverFlyout(
            panel: withPanel
                ? const Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: SizedBox(width: 120, height: 80, child: Text('卡片')),
                  )
                : null,
            builder: (context, hovered) => SizedBox(
              width: 40,
              height: 40,
              child: Text(hovered ? '亮' : '暗'),
            ),
          ),
        ),
      ),
    ));
  }

  /// A mouse that stays on screen between moves, as a real one does.
  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: const Offset(600, 500));
    addTearDown(gesture.removePointer);
    return gesture;
  }

  testWidgets('opens under the pointer and closes after it leaves',
      (tester) async {
    await pump(tester);
    final pointer = await mouse(tester);
    expect(find.text('卡片'), findsNothing);

    await pointer.moveTo(tester.getCenter(find.text('暗')));
    await tester.pumpAndSettle();
    expect(find.text('卡片'), findsOneWidget);

    await pointer.moveTo(const Offset(600, 500));
    await tester.pump(kFlyoutGrace + const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    expect(find.text('卡片'), findsNothing);
  });

  testWidgets('stays open once the pointer is on the panel itself',
      (tester) async {
    await pump(tester);
    final pointer = await mouse(tester);
    await pointer.moveTo(tester.getCenter(find.text('暗')));
    await tester.pumpAndSettle();

    await pointer.moveTo(tester.getCenter(find.text('卡片')));
    await tester.pump(kFlyoutGrace * 3);
    await tester.pumpAndSettle();
    expect(find.text('卡片'), findsOneWidget);
  });

  testWidgets('survives the gap between the two', (tester) async {
    await pump(tester);
    final pointer = await mouse(tester);
    final trigger = tester.getCenter(find.text('亮').evaluate().isEmpty
        ? find.text('暗')
        : find.text('亮'));
    await pointer.moveTo(trigger);
    await tester.pumpAndSettle();

    // Off the trigger, into the dead space, and onto the panel — within the
    // grace period, which is the whole point of having one.
    await pointer.moveTo(Offset(trigger.dx + 45, trigger.dy));
    await tester.pump(const Duration(milliseconds: 60));
    await pointer.moveTo(tester.getCenter(find.text('卡片')));
    await tester.pump(kFlyoutGrace * 3);
    await tester.pumpAndSettle();
    expect(find.text('卡片'), findsOneWidget);
  });

  testWidgets('keeps the trigger lit while its panel is being read',
      (tester) async {
    await pump(tester);
    final pointer = await mouse(tester);
    await pointer.moveTo(tester.getCenter(find.text('暗')));
    await tester.pumpAndSettle();
    expect(find.text('亮'), findsOneWidget);

    await pointer.moveTo(tester.getCenter(find.text('卡片')));
    await tester.pumpAndSettle();
    expect(find.text('亮'), findsOneWidget, reason: 'the block is still active');
  });

  testWidgets('opens from the trigger\'s top right corner', (tester) async {
    await pump(tester);
    final pointer = await mouse(tester);
    await pointer.moveTo(tester.getCenter(find.text('暗')));
    await tester.pumpAndSettle();

    // The panel hangs off the trigger's outer edge and starts level with its
    // top, which is what keeps a card beside the first rail block on screen
    // instead of half of it above the window.
    final corner = tester.getTopRight(find.byType(SizedBox).first);
    final panel = tester.getTopLeft(find.text('卡片'));
    expect(panel.dx, greaterThanOrEqualTo(corner.dx));
    expect(panel.dy, closeTo(corner.dy, 1));
  });

  testWidgets('a trigger with no panel is just a hover region', (tester) async {
    await pump(tester, withPanel: false);
    final pointer = await mouse(tester);
    await pointer.moveTo(tester.getCenter(find.text('暗')));
    await tester.pumpAndSettle();
    expect(find.text('亮'), findsOneWidget);
    expect(find.text('卡片'), findsNothing);
  });

  testWidgets('an open panel taken away closes rather than lingering',
      (tester) async {
    await pump(tester);
    final pointer = await mouse(tester);
    await pointer.moveTo(tester.getCenter(find.text('暗')));
    await tester.pumpAndSettle();
    expect(find.text('卡片'), findsOneWidget);

    // What clearing the token in settings does to the card on screen.
    await pump(tester, withPanel: false);
    await tester.pumpAndSettle();
    expect(find.text('卡片'), findsNothing);
  });
}
