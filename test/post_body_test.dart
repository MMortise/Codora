import 'package:codora/app_theme.dart';
import 'package:codora/core/models.dart';
import 'package:codora/widgets/post_body.dart';
import 'package:codora/widgets/post_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpBody(WidgetTester tester, String content, BodyFormat format) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(
      body: SingleChildScrollView(
        child: PostBody(
          content: content,
          format: format,
          baseUrl: Uri.parse('https://example.com'),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The clipped corner every picture in a post body gets, so a Markdown post
/// and an HTML post cannot drift apart.
double? cornerOf(WidgetTester tester, Finder image) {
  final clip = tester.widgetList<ClipRRect>(
    find.descendant(of: image, matching: find.byType(ClipRRect)),
  );
  if (clip.isEmpty) return null;
  final radius = clip.first.borderRadius;
  return radius is BorderRadius ? radius.topLeft.x : null;
}

void main() {
  group('HTML bodies', () {
    testWidgets('hides Discourse lightbox captions, keeps body text',
        (tester) async {
      await pumpBody(
        tester,
        '<p>正文内容</p>'
        '<div class="lightbox-wrapper"><a class="lightbox" href="https://example.com/x">'
        '<div class="meta"><span class="filename">image</span>'
        '<span class="informations">1411×1269 280 KB</span></div></a></div>'
        '<pre><code>print(1)</code></pre>',
        BodyFormat.html,
      );
      expect(find.textContaining('正文内容', findRichText: true), findsOneWidget);
      expect(find.textContaining('280 KB', findRichText: true), findsNothing);
      expect(find.textContaining('image', findRichText: true), findsNothing);
      expect(find.textContaining('print(1)', findRichText: true), findsOneWidget);
    });

    testWidgets('rounds content images and leaves emoji alone', (tester) async {
      await pumpBody(
        tester,
        '<p>看图 <img class="emoji" src="/e.png" alt="smile"></p>'
        '<p><img src="/photo.png" alt="photo"></p>',
        BodyFormat.html,
      );
      final images = tester.widgetList<PostImage>(find.byType(PostImage)).toList();
      expect(images.length, 2);

      final emoji = images.firstWhere((i) => i.alt == 'smile');
      final photo = images.firstWhere((i) => i.alt == 'photo');
      expect(emoji.rounded, isFalse, reason: 'clipping a 20px glyph cuts it');
      expect(photo.rounded, isTrue);

      expect(cornerOf(tester, find.byWidget(photo)), Radii.image);
      expect(cornerOf(tester, find.byWidget(emoji)), isNull);
    });

    testWidgets('resolves relative image urls against the site', (tester) async {
      await pumpBody(tester, '<p><img src="/a/b.png"></p>', BodyFormat.html);
      final image = tester.widget<PostImage>(find.byType(PostImage));
      expect(image.url.toString(), 'https://example.com/a/b.png');
    });
  });

  group('Markdown bodies', () {
    testWidgets('renders headings, text and code', (tester) async {
      await pumpBody(
        tester,
        '# 标题\n\n正文一段。\n\n```dart\nvoid main() {}\n```\n',
        BodyFormat.markdown,
      );
      expect(find.textContaining('标题', findRichText: true), findsOneWidget);
      expect(find.textContaining('正文一段', findRichText: true), findsOneWidget);
      expect(find.textContaining('void main()', findRichText: true), findsOneWidget);
    });

    testWidgets('images match the corner radius HTML bodies use',
        (tester) async {
      await pumpBody(
        tester,
        '![photo](https://example.com/photo.png)',
        BodyFormat.markdown,
      );
      final image = tester.widget<PostImage>(find.byType(PostImage));
      expect(image.rounded, isTrue);
      expect(cornerOf(tester, find.byType(PostImage)), Radii.image);
    });

    testWidgets('resolves relative image urls against the site', (tester) async {
      await pumpBody(tester, '![x](/a/b.png)', BodyFormat.markdown);
      final image = tester.widget<PostImage>(find.byType(PostImage));
      expect(image.url.toString(), 'https://example.com/a/b.png');
    });
  });

  // Both renderers hand a preformatted block to a horizontal scroll view,
  // which suits a listing of code and nothing else people put in one. A V2EX
  // post written entirely inside `<pre>` came out as one line per paragraph,
  // reachable only by dragging sideways inside a pane that scrolls the other
  // way.
  group('preformatted blocks', () {
    const long = '一段很长的正文，作者把整篇帖子都写在了一个块里面，所以这一行会一直'
        '延伸下去，直到读者只能横着拖动才能把它读完，而这恰恰是一个阅读器最不该'
        '要求读者做的事情。';

    /// A pane narrow enough that the line above cannot possibly fit on one.
    void narrow(WidgetTester tester) {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    bool scrollsSideways(WidgetTester tester) => tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .any((s) => s.scrollDirection == Axis.horizontal);

    testWidgets('a long line wraps rather than running off the side',
        (tester) async {
      narrow(tester);
      await pumpBody(tester, '<pre><code>$long</code></pre>', BodyFormat.html);

      final box = tester.getSize(find.text(long));
      expect(box.width, lessThanOrEqualTo(400));
      expect(box.height, greaterThan(40), reason: 'which takes several lines');
      expect(scrollsSideways(tester), isFalse);
    });

    testWidgets('the line breaks the author wrote are kept', (tester) async {
      // Wrapping by telling the renderer `white-space: normal` would have
      // thrown these away, and they are the one part that cannot be guessed
      // back — they carry the numbered lists these posts are full of.
      narrow(tester);
      await pumpBody(
          tester, '<pre><code>\n1. 第一条\n2. 第二条\n</code></pre>', BodyFormat.html);

      expect(find.text('1. 第一条\n2. 第二条'), findsOneWidget,
          reason: 'without the blank lines the markup puts around a block');
    });

    testWidgets('a markdown code block wraps the same way', (tester) async {
      narrow(tester);
      await pumpBody(tester, '```\n$long\n```\n', BodyFormat.markdown);

      expect(tester.getSize(find.text(long)).width, lessThanOrEqualTo(400));
      expect(scrollsSideways(tester), isFalse);
    });

    testWidgets('and still sits on the raised block it had', (tester) async {
      narrow(tester);
      await pumpBody(tester, '<pre><code>print(1)</code></pre>', BodyFormat.html);

      final box = tester.widget<Container>(find.ancestor(
          of: find.text('print(1)'), matching: find.byType(Container)).first);
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, Palette.dark.raised);
      expect((decoration.borderRadius! as BorderRadius).topLeft.x, Radii.image);
    });
  });
}
