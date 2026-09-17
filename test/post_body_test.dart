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
}
