// Draws real post bodies from each site and checks every picture comes out
// the same shape. The fixtures are the markup the sites actually serve, which
// is where the shapes differ: Discourse wraps images in a lightbox anchor,
// V2EX tags them with a class and a srcset.
import 'dart:io';

import 'package:codora/app_theme.dart';
import 'package:codora/core/models.dart';
import 'package:codora/widgets/post_body.dart';
import 'package:codora/widgets/post_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<PostImage>> drawAndCollect(
  WidgetTester tester,
  String content,
  BodyFormat format,
  Uri baseUrl,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(
      body: SingleChildScrollView(
        child: PostBody(content: content, format: format, baseUrl: baseUrl),
      ),
    ),
  ));
  await tester.pump();
  expect(tester.takeException(), isNull);
  return tester.widgetList<PostImage>(find.byType(PostImage)).toList();
}

double? cornerOf(WidgetTester tester, PostImage image) {
  final clips = tester.widgetList<ClipRRect>(
    find.descendant(of: find.byWidget(image), matching: find.byType(ClipRRect)),
  );
  if (clips.isEmpty) return null;
  final radius = clips.first.borderRadius;
  return radius is BorderRadius ? radius.topLeft.x : null;
}

void main() {
  final linuxdo = File('test/fixtures/linuxdo_post.html').readAsStringSync();
  final v2ex = File('test/fixtures/v2ex_post.html').readAsStringSync();

  testWidgets('linux.do lightbox images are rounded', (tester) async {
    final images = await drawAndCollect(
        tester, linuxdo, BodyFormat.html, Uri.parse('https://linux.do'));

    expect(images, hasLength(2), reason: 'the fixture has two lightbox images');
    for (final image in images) {
      expect(image.rounded, isTrue, reason: '${image.url}');
      expect(cornerOf(tester, image), Radii.image, reason: '${image.url}');
      expect(image.url.host, 'cdn3.ldstatic.com');
    }
  });

  testWidgets('linux.do lightbox captions stay hidden', (tester) async {
    await drawAndCollect(
        tester, linuxdo, BodyFormat.html, Uri.parse('https://linux.do'));

    // Pixel dimensions and file size only ever appear in the caption, so they
    // are the honest signal. The file name is not: it is also the image's alt
    // text, which the placeholder shows when a picture cannot load.
    for (final caption in ['182 KB', '232 KB', '2756', '2770']) {
      expect(find.textContaining(caption, findRichText: true), findsNothing,
          reason: 'caption fragment "$caption" leaked into the post');
    }
  });

  testWidgets('V2EX embedded images are rounded', (tester) async {
    final images = await drawAndCollect(
        tester, v2ex, BodyFormat.html, Uri.parse('https://www.v2ex.com'));

    expect(images, isNotEmpty);
    for (final image in images) {
      expect(image.rounded, isTrue, reason: '${image.url}');
      expect(cornerOf(tester, image), Radii.image, reason: '${image.url}');
      expect(image.url.hasScheme, isTrue, reason: '${image.url}');
    }
  });

  testWidgets('all three sites land on the same corner', (tester) async {
    // Each corner is read while its own tree is still mounted; pumping the
    // next body disposes the previous one.
    Future<double?> firstCorner(String content, BodyFormat format, String base) async {
      final images =
          await drawAndCollect(tester, content, format, Uri.parse(base));
      expect(images, isNotEmpty);
      return cornerOf(tester, images.first);
    }

    final corners = {
      'juejin (markdown)': await firstCorner(
          '![x](https://example.com/a.png)', BodyFormat.markdown, 'https://juejin.cn'),
      'linux.do (html)':
          await firstCorner(linuxdo, BodyFormat.html, 'https://linux.do'),
      'v2ex (html)':
          await firstCorner(v2ex, BodyFormat.html, 'https://www.v2ex.com'),
    };

    expect(corners.values.toSet(), {Radii.image}, reason: '$corners');
  });
}
