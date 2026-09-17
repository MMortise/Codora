// Pictures in posts arrive at whatever size the site uploaded. linux.do serves
// originals thousands of pixels wide, so one that is not held to the pane
// width spills past it: the rounded corners end up off screen and the height,
// scaled from the original, leaves a large gap.
//
// The fixtures are real PNGs and the test lets them decode. A test where the
// image fails to load exercises the placeholder instead, which is exactly how
// this went unnoticed.
import 'dart:io';
import 'dart:typed_data';

import 'package:codora/app_theme.dart';
import 'package:codora/core/forum_source.dart';
import 'package:codora/core/models.dart';
import 'package:codora/widgets/post_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const paneWidth = 560.0;

Uint8List bytesOf(String name) => File('test/fixtures/$name').readAsBytesSync();

/// Renders a post body through the real pipeline, with the picture supplied by
/// a loader so it genuinely decodes under test.
Future<void> pumpPost(
  WidgetTester tester,
  String content,
  BodyFormat format,
  String fixture,
) async {
  final bytes = bytesOf(fixture);
  final app = MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: paneWidth,
          child: SingleChildScrollView(
            child: PostBody(
              content: content,
              format: format,
              baseUrl: Uri.parse('https://linux.do'),
              images: SiteImages(loader: (_) async => bytes),
            ),
          ),
        ),
      ),
    ),
  );

  // Decoding is real async work. Under test it only happens inside runAsync,
  // and the image has to be precached before it reports a size.
  await tester.runAsync(() async {
    await tester.pumpWidget(app);
    // Let the loader future settle so the Image widget is built at all.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();

    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
    await tester.pump();
  });
  await tester.pumpAndSettle();
}

Rect imageRect(WidgetTester tester) {
  final image = find.byType(RawImage);
  expect(image, findsWidgets, reason: 'the picture should have decoded');
  return tester.getRect(image.first);
}

void main() {
  group('an oversized picture', () {
    const html = '<p><img src="https://cdn3.ldstatic.com/wide.png" alt="wide"></p>';

    testWidgets('is scaled down to the pane', (tester) async {
      await pumpPost(tester, html, BodyFormat.html, 'wide_image.png');
      expect(tester.takeException(), isNull);

      final rect = imageRect(tester);
      expect(rect.width, lessThanOrEqualTo(paneWidth),
          reason: 'a 2756px picture must not spill out of a 560px pane');
      expect(rect.height / rect.width, closeTo(1400 / 2756, 0.05),
          reason: 'its shape must survive the fit');
    });

    testWidgets('keeps its rounded corners on screen', (tester) async {
      await pumpPost(tester, html, BodyFormat.html, 'wide_image.png');
      final clip = tester.getRect(find.byType(ClipRRect).first);
      expect(clip.width, lessThanOrEqualTo(paneWidth),
          reason: 'corners clipped outside the pane cannot be seen');
      expect(clip.width, closeTo(imageRect(tester).width, 2));
    });

    testWidgets('does not leave a tall empty gap', (tester) async {
      await pumpPost(tester, html, BodyFormat.html, 'wide_image.png');
      final rect = imageRect(tester);
      // At the pane width this picture is about 284px tall. Anything near the
      // original 1400 means it was laid out unscaled.
      expect(rect.height, lessThan(400),
          reason: 'height scaled from the original leaves a huge gap');
    });
  });

  testWidgets('a small picture is not blown up', (tester) async {
    await pumpPost(
      tester,
      '<p><img src="https://cdn3.ldstatic.com/small.png" alt="small"></p>',
      BodyFormat.html,
      'small_image.png',
    );
    final rect = imageRect(tester);
    expect(rect.width, closeTo(120, 2), reason: '120px should stay 120px');
    expect(rect.height, closeTo(80, 2));
  });

  testWidgets('a tall picture is bounded by width', (tester) async {
    await pumpPost(
      tester,
      '<p><img src="https://cdn3.ldstatic.com/tall.png" alt="tall"></p>',
      BodyFormat.html,
      'tall_image.png',
    );
    final rect = imageRect(tester);
    expect(rect.width, lessThanOrEqualTo(paneWidth));
    expect(rect.height / rect.width, closeTo(3000 / 750, 0.05));
  });

  testWidgets('markdown pictures are bounded the same way', (tester) async {
    await pumpPost(
      tester,
      '![wide](https://cdn3.ldstatic.com/wide.png)',
      BodyFormat.markdown,
      'wide_image.png',
    );
    final rect = imageRect(tester);
    expect(rect.width, lessThanOrEqualTo(paneWidth),
        reason: 'both renderers must agree');
  });
}
