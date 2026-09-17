import 'package:codora/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The settings page puts a button next to a text field on one row. They only
/// line up if each control's natural height is the shared one, so pinning a
/// row to [kControlHeight] never squashes what is inside it.
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
            const SizedBox(
              width: 220,
              child: TextField(decoration: InputDecoration(labelText: 'Token')),
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

      // A single-line field must not be taller than the row it gets pinned to.
      expect(tester.getSize(find.byType(TextField)).height,
          lessThanOrEqualTo(kControlHeight));
    });
  }

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
