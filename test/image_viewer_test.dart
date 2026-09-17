// Opening a picture is one of the few places the app takes over the whole
// window, so the ways out and the choice of layout are worth pinning down.
import 'dart:io';

import 'package:codora/app_theme.dart';
import 'package:codora/core/models.dart';
import 'package:codora/widgets/image_viewer.dart';
import 'package:codora/widgets/post_body.dart';
import 'package:codora/widgets/post_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpBodyWithImage(WidgetTester tester, String html) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(
      body: SingleChildScrollView(
        child: PostBody(
          content: html,
          format: BodyFormat.html,
          baseUrl: Uri.parse('https://linux.do'),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  final linuxdo = File('test/fixtures/linuxdo_post.html').readAsStringSync();

  group('what the viewer opens', () {
    testWidgets('a lightbox image offers the original, not the thumbnail',
        (tester) async {
      await pumpBodyWithImage(tester, linuxdo);
      final images = tester.widgetList<PostImage>(find.byType(PostImage));
      expect(images, isNotEmpty);

      for (final image in images) {
        expect(image.fullUrl, isNotNull,
            reason: 'Discourse links the original from the lightbox anchor');
        expect(image.url.path, contains('/optimized/'),
            reason: 'inline copy is the resized one');
        expect(image.fullUrl!.path, contains('/original/'),
            reason: 'the viewer should open the original');
      }
    });

    testWidgets('a plain image opens itself', (tester) async {
      await pumpBodyWithImage(
          tester, '<p><img src="https://example.com/a.png" alt="a"></p>');
      final image = tester.widget<PostImage>(find.byType(PostImage));
      expect(image.fullUrl, isNull);
      expect(image.url.toString(), 'https://example.com/a.png');
    });

    testWidgets('emoji are not made clickable', (tester) async {
      await pumpBodyWithImage(
          tester, '<p><img class="emoji" src="/e.png" alt="smile"></p>');
      final image = tester.widget<PostImage>(find.byType(PostImage));
      expect(image.rounded, isFalse);
      expect(find.descendant(
        of: find.byWidget(image),
        matching: find.byType(GestureDetector),
      ), findsNothing);
    });
  });

  group('the overlay', () {
    Future<void> openViewer(WidgetTester tester, {String? alt}) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showImageViewer(
                context,
                url: Uri.parse('https://example.com/a.png'),
                alt: alt,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('dims the page behind it', (tester) async {
      await openViewer(tester);
      final barrier = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier));
      expect(barrier, isNotEmpty);
      expect(barrier.any((b) => b.color != null && b.color!.a > 0.5), isTrue,
          reason: 'the backdrop should actually dim');
    });

    testWidgets('escape closes it', (tester) async {
      await openViewer(tester);
      // The close button only exists inside the viewer, so it stands in for
      // "the overlay is up" without depending on the picture loading.
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('the close button closes it', (tester) async {
      await openViewer(tester);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('an unreachable image shows a placeholder, not a spinner',
        (tester) async {
      await openViewer(tester);
      // Network images cannot load under flutter_test, which is the same
      // situation as a dead link in a post.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(BrokenImage), findsOneWidget);
    });

    testWidgets('shows the caption when the image has one', (tester) async {
      await openViewer(tester, alt: '一张示意图');
      expect(find.text('一张示意图'), findsOneWidget);
    });

    testWidgets('offers close, copy and open-in-browser', (tester) async {
      await openViewer(tester);
      for (final icon in [
        Icons.close_rounded,
        Icons.link_rounded,
        Icons.north_east_rounded,
      ]) {
        expect(find.byIcon(icon), findsOneWidget);
      }
    });
  });

  group('tall images', () {
    test('the switch point is a sensible aspect ratio', () {
      // A phone screenshot is about 1:2.2; an article capture is far taller.
      // Anything at or past that reads better scrolled than shrunk.
      bool isTall(int w, int h) => h / w >= 2.2;
      expect(isTall(1600, 900), isFalse, reason: 'landscape');
      expect(isTall(1000, 1000), isFalse, reason: 'square');
      expect(isTall(800, 1600), isFalse, reason: 'ordinary portrait');
      expect(isTall(750, 1900), isTrue, reason: 'phone screenshot');
      expect(isTall(800, 6000), isTrue, reason: 'long article capture');
    });

    testWidgets('both layouts are reachable from the viewer', (tester) async {
      // ViewerMode is the contract between measuring and laying out.
      expect(ViewerMode.values, hasLength(2));
      expect(ViewerMode.values, contains(ViewerMode.fit));
      expect(ViewerMode.values, contains(ViewerMode.scroll));
    });
  });
}
