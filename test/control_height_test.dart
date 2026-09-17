import 'package:codora/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The settings page puts a button next to a text field on one row. They line
/// up because each control's natural height is the shared one — and the field
/// treats it as a floor rather than a fixed size, so it can never come out
/// shorter than the button beside it.
///
/// What the reader compares is the *painted outline*, not the box Flutter
/// lays out around it. Those are not the same thing: a `minHeight` on the
/// decoration stretches the outer box and leaves the outline short inside it,
/// so a field can measure 40 to `getSize` while looking 6px under the button
/// next to it. That is exactly what happened, twice, so the outline is what
/// is measured here.
double outlineHeight(WidgetTester tester, [Finder? within]) {
  final outline = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_BorderContainer');
  return tester
      .getRect(within == null
          ? outline.first
          : find.descendant(of: within, matching: outline))
      .height;
}

void main() {
  Future<void> pump(WidgetTester tester, Brightness brightness) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(brightness),
      home: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilledButton(onPressed: () {}, child: const Text('保存')),
            OutlinedButton(onPressed: () {}, child: const Text('清除凭据')),
            SizedBox(
              width: 220,
              child: TextField(
                // Filled in, so the label floats. An empty field measured
                // right while a filled one did not.
                controller: TextEditingController(text: 'abcdef'),
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(labelText: 'Token'),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets('controls share one height in ${brightness.name}', (tester) async {
      await pump(tester, brightness);

      expect(tester.getSize(find.byType(FilledButton)).height, kControlHeight);
      expect(tester.getSize(find.byType(OutlinedButton)).height, kControlHeight);

      // A single-line field starts out level with the buttons, and is never
      // allowed to come out shorter than them.
      expect(tester.getSize(find.byType(TextField)).height, kControlHeight);

      // The part with a visible edge, which is what anyone actually compares.
      expect(outlineHeight(tester), kControlHeight,
          reason: 'the field is drawn shorter than the button beside it');
    });
  }

  for (final brightness in Brightness.values) {
    test('both buttons are filled blocks in ${brightness.name}', () {
      // They always measured the same height, but a bare outline on the
      // panel's own colour reads as a smaller control than a solid one, so
      // the secondary button carries a fill of its own.
      final theme = buildTheme(brightness);
      final p = brightness == Brightness.dark ? Palette.dark : Palette.light;

      for (final (name, style) in [
        ('primary', theme.filledButtonTheme.style),
        ('secondary', theme.outlinedButtonTheme.style),
      ]) {
        final fill = style?.backgroundColor?.resolve({});
        expect(fill, isNotNull,
            reason: 'the $name button has no fill to read as a block');
        expect(fill, isNot(p.panel),
            reason: 'the $name button would vanish into the card it sits on');
      }
    });
  }

  testWidgets('a field scaled up grows instead of being squashed',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: const Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton(onPressed: null, child: Text('保存')),
              SizedBox(
                width: 220,
                child: TextField(decoration: InputDecoration(labelText: 'Token')),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(TextField)).height,
        greaterThanOrEqualTo(kControlHeight),
        reason: 'the shared height is a floor, so bigger text never '
            'leaves the field shorter than the button');
    expect(outlineHeight(tester), greaterThanOrEqualTo(kControlHeight),
        reason: 'and the outline grows with it rather than staying put');
  });

  testWidgets('a disabled button keeps the same height', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Row(children: [
          const FilledButton(onPressed: null, child: Text('保存')),
          const OutlinedButton(onPressed: null, child: Text('清除凭据')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(FilledButton)).height, kControlHeight);
    expect(tester.getSize(find.byType(OutlinedButton)).height, kControlHeight);
  });
}
