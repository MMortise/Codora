// Switching between boards, posts and themes should read as movement, not as
// a cut. These tests step through the animation rather than settling it, so a
// silently removed transition fails here.
import 'package:codora/app_theme.dart';
import 'package:codora/widgets/swap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpSwap(WidgetTester tester, String key) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(
      body: Swap(swapKey: key, child: Text(key, key: ValueKey(key))),
    ),
  ));
}

void main() {
  group('content swaps', () {
    testWidgets('the arriving content fades in rather than appearing',
        (tester) async {
      await pumpSwap(tester, 'first');
      await tester.pumpAndSettle();

      await pumpSwap(tester, 'second');
      await tester.pump();
      await tester.pump(Motion.swap ~/ 2);

      // Halfway through, the new text is on screen but not yet fully opaque.
      final fades = tester.widgetList<FadeTransition>(find.descendant(
        of: find.byType(Swap),
        matching: find.byType(FadeTransition),
      ));
      expect(fades, isNotEmpty);
      expect(fades.any((f) => f.opacity.value > 0 && f.opacity.value < 1), isTrue,
          reason: 'mid-transition opacity should be partial');

      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);
      expect(find.text('first'), findsNothing);
    });

    testWidgets('it also drifts into place', (tester) async {
      await pumpSwap(tester, 'a');
      await tester.pumpAndSettle();
      await pumpSwap(tester, 'b');
      await tester.pump();
      await tester.pump(Motion.swap ~/ 2);

      final slides = tester.widgetList<SlideTransition>(find.descendant(
        of: find.byType(Swap),
        matching: find.byType(SlideTransition),
      ));
      expect(slides.any((s) => s.position.value != Offset.zero), isTrue,
          reason: 'the new content should still be travelling');

      await tester.pumpAndSettle();
      for (final slide in tester.widgetList<SlideTransition>(find.descendant(
          of: find.byType(Swap), matching: find.byType(SlideTransition)))) {
        expect(slide.position.value, Offset.zero, reason: 'it must settle');
      }
    });

    testWidgets('rebuilding with the same key does not animate',
        (tester) async {
      await pumpSwap(tester, 'same');
      await tester.pumpAndSettle();
      await pumpSwap(tester, 'same');
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('same'), findsOneWidget);
    });

    testWidgets('a label can swap without drifting', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const Scaffold(
          body: Swap(swapKey: 'x', drift: 0, child: Text('x')),
        ),
      ));
      await tester.pumpAndSettle();
      // Scoped to the widget: the app's own page route also uses a slide.
      expect(
        find.descendant(
            of: find.byType(Swap), matching: find.byType(SlideTransition)),
        findsNothing,
      );
      expect(
        find.descendant(
            of: find.byType(Swap), matching: find.byType(FadeTransition)),
        findsWidgets,
      );
    });
  });

  group('theme changes', () {
    test('the palette blends instead of snapping', () {
      final mid = Palette.lerp(Palette.dark, Palette.light, 0.5);
      expect(mid.canvas, isNot(Palette.dark.canvas));
      expect(mid.canvas, isNot(Palette.light.canvas));

      // Every colour takes part, so nothing lags behind during the crossfade.
      expect(mid.ink, isNot(Palette.dark.ink));
      expect(mid.panel, isNot(Palette.dark.panel));
      expect(mid.line, isNot(Palette.dark.line));
    });

    test('the ends of the blend are the palettes themselves', () {
      expect(Palette.lerp(Palette.dark, Palette.light, 0).canvas,
          Palette.dark.canvas);
      expect(Palette.lerp(Palette.dark, Palette.light, 1).canvas,
          Palette.light.canvas);
    });

    test('a colour shared by both themes stays put', () {
      // The badge purple is identical in both, so it must not wobble mid-blend.
      expect(Palette.lerp(Palette.dark, Palette.light, 0.5).badge,
          Palette.dark.badge);
    });

    testWidgets('the theme extension animates with the app', (tester) async {
      final theme = buildTheme(Brightness.dark);
      final extension = theme.extension<CodoraTheme>();
      expect(extension, isNotNull);

      final other = buildTheme(Brightness.light).extension<CodoraTheme>()!;
      final mid = extension!.lerp(other, 0.5);
      expect(mid.palette.canvas, isNot(extension.palette.canvas));
    });
  });

  group('the motion scale', () {
    test('is ordered from touch response to full repaint', () {
      expect(Motion.quick, lessThan(Motion.swap));
      expect(Motion.swap, lessThan(Motion.theme));
    });

    test('stays within what reads as instant', () {
      // Past roughly a quarter second an interface starts to feel sluggish.
      expect(Motion.theme.inMilliseconds, lessThanOrEqualTo(250));
      expect(Motion.quick.inMilliseconds, greaterThanOrEqualTo(80),
          reason: 'too short and the change is missed entirely');
    });
  });
}
