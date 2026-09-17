// Draws a real Juejin article with the app's own widget. The fixture is the
// markdown the site actually shipped, so the renderer is exercised against
// real-world input instead of a handwritten sample.
//
// Refresh it with test/fixtures/README.md's instructions.
import 'dart:io';

import 'package:codora/app_theme.dart';
import 'package:codora/core/models.dart';
import 'package:codora/widgets/post_body.dart';
import 'package:codora/widgets/post_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final markdown = File('test/fixtures/juejin_article.md').readAsStringSync();

  Future<void> draw(WidgetTester tester, Brightness brightness) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(brightness),
      home: Scaffold(
        body: SingleChildScrollView(
          child: PostBody(
            content: markdown,
            format: BodyFormat.markdown,
            baseUrl: Uri.parse('https://juejin.cn'),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  test('the fixture looks like a real article', () {
    expect(markdown.length, greaterThan(2000));
    expect(markdown, contains('```'), reason: 'fenced code');
    expect(markdown, contains('#'), reason: 'headings');
  });

  for (final brightness in Brightness.values) {
    testWidgets('renders a real article in ${brightness.name}', (tester) async {
      await draw(tester, brightness);
      expect(tester.takeException(), isNull);
      expect(find.byType(PostBody), findsOneWidget);
      // Something actually got laid out, rather than an empty body.
      expect(tester.getSize(find.byType(PostBody)).height, greaterThan(400));
    });
  }

  testWidgets('code blocks use the monospace family', (tester) async {
    await draw(tester, Brightness.dark);

    // The family can sit on any span, not just the root style.
    // visitChildren already walks the whole subtree.
    var monoSpans = 0;
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      if (rich.text.style?.fontFamily == 'Menlo') monoSpans++;
      rich.text.visitChildren((span) {
        if (span.style?.fontFamily == 'Menlo') monoSpans++;
        return true;
      });
    }
    expect(monoSpans, greaterThan(0), reason: 'fenced code should render as code');
  });

  testWidgets('every picture is rounded', (tester) async {
    await draw(tester, Brightness.dark);
    for (final image in tester.widgetList<PostImage>(find.byType(PostImage))) {
      expect(image.rounded, isTrue);
    }
  });
}
