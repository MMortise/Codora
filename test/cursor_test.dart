// Anything clickable in a post should say so on hover. The two renderers get
// there differently: the HTML one sets a cursor on the link's span, the
// markdown one had no cursor at all until it was given one.
import 'package:codora/app_theme.dart';
import 'package:codora/core/models.dart';
import 'package:codora/widgets/post_body.dart';
import 'package:codora/widgets/chrome.dart';
import 'package:codora/widgets/post_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpBody(
    WidgetTester tester, String content, BodyFormat format) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(
      body: SingleChildScrollView(
        child: PostBody(
          content: content,
          format: format,
          baseUrl: Uri.parse('https://linux.do'),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// Cursor on the widget that actually carries [label], not merely somewhere
/// in the body. Asserting on the whole subtree passes for the wrong reasons.
MouseCursor? cursorOnText(WidgetTester tester, String label) {
  final regions = find.ancestor(
    of: find.text(label),
    matching: find.byType(MouseRegion),
  );
  if (regions.evaluate().isEmpty) return null;
  return tester.widget<MouseRegion>(regions.first).cursor;
}

/// Cursor on the inline span whose text is [label]. HTML links are spans
/// inside one paragraph, so they have no widget of their own.
MouseCursor? cursorOnSpan(WidgetTester tester, String label) {
  MouseCursor? found;
  for (final rich in tester.widgetList<RichText>(find.descendant(
    of: find.byType(PostBody),
    matching: find.byType(RichText),
  ))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text == label) {
        found = span.mouseCursor;
        return false;
      }
      return true;
    });
    if (found != null) break;
  }
  return found;
}

void main() {
  group('links', () {
    testWidgets('an HTML link shows a pointer', (tester) async {
      await pumpBody(
        tester,
        '<p>看看 <a href="https://example.com">这个链接</a> 吧</p>',
        BodyFormat.html,
      );
      expect(cursorOnSpan(tester, '这个链接'), SystemMouseCursors.click,
          reason: 'the link span itself must announce it');
    });

    testWidgets('a markdown link shows a pointer', (tester) async {
      await pumpBody(
        tester,
        '看看 [这个链接](https://example.com) 吧',
        BodyFormat.markdown,
      );
      expect(cursorOnText(tester, '这个链接'), SystemMouseCursors.click,
          reason: 'the link itself must announce it, not the body around it');
    });

    testWidgets('a markdown link still reads as its own text', (tester) async {
      await pumpBody(
        tester,
        '看看 [这个链接](https://example.com) 吧',
        BodyFormat.markdown,
      );
      expect(find.text('这个链接'), findsOneWidget,
          reason: 'the label must survive the custom builder');
    });

    testWidgets('plain text does not claim to be clickable', (tester) async {
      await pumpBody(tester, '<p>只是一段普通文字</p>', BodyFormat.html);
      expect(cursorOnSpan(tester, '只是一段普通文字'),
          anyOf(isNull, MouseCursor.defer));
    });

    testWidgets('plain markdown does not either', (tester) async {
      await pumpBody(tester, '只是一段普通文字', BodyFormat.markdown);
      expect(cursorOnText(tester, '只是一段普通文字'), isNull,
          reason: 'plain text should not be wrapped in a clickable region');
    });
  });

  group('images', () {
    testWidgets('a picture shows a pointer, since it opens', (tester) async {
      await pumpBody(
        tester,
        '<p><img src="https://cdn3.ldstatic.com/a.png" alt="a"></p>',
        BodyFormat.html,
      );
      final region = tester.widget<MouseRegion>(find.descendant(
        of: find.byType(PostImage),
        matching: find.byType(MouseRegion),
      ).first);
      expect(region.cursor, SystemMouseCursors.click);
    });

    testWidgets('an emoji does not, since it does nothing', (tester) async {
      await pumpBody(
        tester,
        '<p><img class="emoji" src="/e.png" alt="smile"></p>',
        BodyFormat.html,
      );
      expect(
        find.descendant(
            of: find.byType(PostImage), matching: find.byType(MouseRegion)),
        findsNothing,
      );
    });

    testWidgets('a markdown picture shows a pointer too', (tester) async {
      await pumpBody(
        tester,
        '![a](https://cdn3.ldstatic.com/a.png)',
        BodyFormat.markdown,
      );
      final region = tester.widget<MouseRegion>(find.descendant(
        of: find.byType(PostImage),
        matching: find.byType(MouseRegion),
      ).first);
      expect(region.cursor, SystemMouseCursors.click);
    });
  });

  group('toolbar buttons', () {
    Future<void> pumpButton(WidgetTester tester, {required bool enabled}) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: QuietIconButton(
            icon: Icons.refresh_rounded,
            tooltip: '重新加载',
            onPressed: enabled ? () {} : null,
          ),
        ),
      ));
      await tester.pump();
    }

    MouseCursor cursorOf(WidgetTester tester) => tester
        .widgetList<MouseRegion>(find.descendant(
          of: find.byType(QuietIconButton),
          matching: find.byType(MouseRegion),
        ))
        .map((r) => r.cursor)
        .firstWhere((c) => c != MouseCursor.defer);

    testWidgets('an available one shows a pointer', (tester) async {
      await pumpButton(tester, enabled: true);
      expect(cursorOf(tester), SystemMouseCursors.click);
    });

    testWidgets('a disabled one refuses the pointer', (tester) async {
      await pumpButton(tester, enabled: false);
      // The colour alone is easy to miss on a small icon.
      expect(cursorOf(tester), SystemMouseCursors.forbidden);
    });
  });
}
