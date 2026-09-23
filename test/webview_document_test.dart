// The hidden WebView linux.do is read through opens a small static page, not
// the forum. What it has to notice about that page is only whether Cloudflare
// stood in front of it — and say so the way a refused request already does.
import 'package:codora/core/webview_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the page is one with no script of its own', () {
    expect(kDocumentPath, '/robots.txt');
    expect(Uri.parse('https://linux.do').resolve(kDocumentPath).toString(),
        'https://linux.do/robots.txt');
  });

  test('robots.txt as served is a page to run requests from', () {
    // A text document has no title; WebKit reports it as empty or absent.
    expect(documentRefusal(null, null), isNull);
    expect(documentRefusal(null, ''), isNull);
    expect(documentRefusal(200, 'robots.txt'), isNull);
  });

  test('a challenge in front of it is reported as one', () {
    final refused = documentRefusal(403, 'Just a moment...');
    expect(refused, isNotNull);
    expect(refused!.isChallenge, isTrue);
    expect(refused.status, 403);

    expect(documentRefusal(503, '')!.isChallenge, isTrue);
    // However the page came to be answered, its title gives it away.
    expect(documentRefusal(null, 'Just a moment...')!.isChallenge, isTrue);
  });

  test('any other answer still leaves a document on the origin', () {
    expect(documentRefusal(404, 'Page Not Found'), isNull);
    expect(documentRefusal(500, ''), isNull);
  });
}
