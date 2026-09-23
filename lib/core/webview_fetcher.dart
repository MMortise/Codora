import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Fetches JSON from inside a real WebView.
///
/// Cloudflare ties a `cf_clearance` cookie to the client that earned it, down
/// to its TLS and HTTP/2 fingerprint. Replaying the cookie from an HTTP client
/// therefore still gets a 403. Running the request as same-origin `fetch` in
/// the very browser that passed the challenge sidesteps that: identical
/// fingerprint, identical cookie jar.
///
/// One hidden WebView is kept per origin and reused. It opens a small static
/// page on the origin rather than the site itself: see [_Session.start].
class WebViewFetcher {
  WebViewFetcher._();
  static final instance = WebViewFetcher._();

  final _sessions = <String, _Session>{};

  Future<_Session> _session(Uri origin, String userAgent) async {
    final key = '${origin.origin}|$userAgent';
    final existing = _sessions[key];
    if (existing != null) {
      await existing.ready;
      return existing;
    }
    final session = _Session(origin, userAgent);
    _sessions[key] = session;
    try {
      await session.start();
    } catch (e) {
      _sessions.remove(key);
      rethrow;
    }
    return session;
  }

  /// GETs [path] on [origin] and returns the decoded JSON body.
  ///
  /// Throws [WebViewFetchException] with the real status code when the site
  /// answers with an error, so callers can tell "challenge" from "not found".
  Future<Object?> getJson(
    Uri origin,
    String path, {
    required String userAgent,
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _json(origin, path, userAgent: userAgent, timeout: timeout);

  /// Sends a write and returns the decoded answer.
  ///
  /// Everything [getJson] says applies here and then some: a write has to
  /// carry the session the site issued, and the session the site issued is
  /// the one in this browser. [headers] is where a site's own condition goes
  /// — Discourse will not take a write without the CSRF token it handed out.
  ///
  /// [method] because a write's shape is the site's business: Discourse takes
  /// a like as a POST and the taking back of one as a DELETE of the same
  /// thing. [body] may be left out for a write that says everything in its
  /// path.
  ///
  /// The status comes back on the exception rather than as a thrown string,
  /// because a refusal here is usually the site explaining itself (too short,
  /// too soon, the topic is closed) and the caller is the one that knows how
  /// to read it.
  Future<Object?> sendJson(
    Uri origin,
    String path, {
    required String method,
    required String userAgent,
    Object? body,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 30),
  }) =>
      _json(origin, path,
          userAgent: userAgent,
          method: method,
          body: body == null ? null : jsonEncode(body),
          headers: headers,
          timeout: timeout);

  Future<Object?> _json(
    Uri origin,
    String path, {
    required String userAgent,
    required Duration timeout,
    String method = 'GET',
    String? body,
    Map<String, String> headers = const {},
  }) async {
    final session = await _session(origin, userAgent);
    final result = await session.controller
        .callAsyncJavaScript(
          functionBody: '''
            try {
              const init = {
                method: method,
                credentials: 'include',
                // Every one of these asks for the state of something right
                // now. Left to the browser's own rules a read can be answered
                // from a cache, which is how a card could be refreshed and
                // come back with the number it already had.
                cache: 'no-store',
                headers: Object.assign({
                  'Accept': 'application/json',
                  'X-Requested-With': 'XMLHttpRequest',
                  'Discourse-Present': 'true',
                }, headers),
              };
              if (body !== null && body !== undefined) {
                init.body = body;
                init.headers['Content-Type'] = 'application/json';
              }
              const res = await fetch(path, init);
              const text = await res.text();
              return { ok: true, status: res.status, body: text };
            } catch (e) {
              return { ok: false, status: 0, body: String(e) };
            }
          ''',
          arguments: {
            'path': path,
            'method': method,
            'body': body,
            'headers': headers,
          },
        )
        .timeout(timeout);

    return _decode(result);
  }

  /// Sends a file the way the site's own page would.
  ///
  /// Everything [sendJson] says applies, and one thing more: an upload goes as
  /// `multipart/form-data`, whose boundary the browser writes. So no content
  /// type is set here — setting one would send a boundary nothing had used —
  /// and the bytes travel to the page as base64, which is what can be handed
  /// over the bridge.
  ///
  /// Slower than everything else here by the size of the picture, so the
  /// patience is its own.
  Future<Object?> sendFile(
    Uri origin,
    String path, {
    required String userAgent,
    required String field,
    required String filename,
    required Uint8List bytes,
    String contentType = 'application/octet-stream',
    Map<String, String> fields = const {},
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final session = await _session(origin, userAgent);
    final result = await session.controller
        .callAsyncJavaScript(
          functionBody: '''
            try {
              const binary = atob(data);
              const bytes = new Uint8Array(binary.length);
              for (let i = 0; i < binary.length; i++) {
                bytes[i] = binary.charCodeAt(i);
              }
              const form = new FormData();
              for (const name of Object.keys(fields)) {
                form.append(name, fields[name]);
              }
              form.append(field, new File([bytes], filename,
                  { type: contentType }));
              const res = await fetch(path, {
                method: 'POST',
                credentials: 'include',
                cache: 'no-store',
                headers: Object.assign({
                  'Accept': 'application/json',
                  'X-Requested-With': 'XMLHttpRequest',
                  'Discourse-Present': 'true',
                }, headers),
                body: form,
              });
              const text = await res.text();
              return { ok: true, status: res.status, body: text };
            } catch (e) {
              return { ok: false, status: 0, body: String(e) };
            }
          ''',
          arguments: {
            'path': path,
            'data': base64Encode(bytes),
            'field': field,
            'filename': filename,
            'contentType': contentType,
            'fields': fields,
            'headers': headers,
          },
        )
        .timeout(timeout);

    return _decode(result);
  }

  /// What the page answered, or the reason there is nothing to read.
  Object? _decode(CallAsyncJavaScriptResult? result) {
    if (result == null || result.error != null) {
      throw WebViewFetchException(0, result?.error ?? '页面脚本没有返回结果');
    }
    final value = result.value;
    if (value is! Map) throw WebViewFetchException(0, '页面脚本返回了意外的结果');
    final status = (value['status'] as num?)?.toInt() ?? 0;
    final text = '${value['body'] ?? ''}';
    if (value['ok'] != true) throw WebViewFetchException(status, text);
    if (status >= 400) throw WebViewFetchException(status, text);
    if (text.trimLeft().startsWith('<')) {
      throw WebViewFetchException(status, '收到的是网页而不是数据');
    }
    try {
      return jsonDecode(text);
    } on FormatException {
      throw WebViewFetchException(status, '返回内容不是 JSON');
    }
  }

  /// GETs [url] and returns the raw bytes, for images the same protection
  /// blocks. Results are cached in memory because lists repeat avatars.
  Future<Uint8List> getBytes(
    Uri origin,
    Uri url, {
    required String userAgent,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final key = url.toString();
    final cached = _imageCache[key];
    if (cached != null) return cached;

    final inFlight = _imageInFlight[key];
    if (inFlight != null) return inFlight;

    final future = _fetchBytes(origin, url, userAgent, timeout);
    _imageInFlight[key] = future;
    try {
      final bytes = await future;
      if (_imageCache.length >= _imageCacheLimit) {
        _imageCache.remove(_imageCache.keys.first);
      }
      _imageCache[key] = bytes;
      return bytes;
    } finally {
      _imageInFlight.remove(key);
    }
  }

  Future<Uint8List> _fetchBytes(
      Uri origin, Uri url, String userAgent, Duration timeout) async {
    final session = await _session(origin, userAgent);
    final result = await session.controller
        .callAsyncJavaScript(
          functionBody: '''
            try {
              const res = await fetch(url, { credentials: 'include' });
              if (!res.ok) return { ok: false, status: res.status, body: '' };
              const buf = await res.arrayBuffer();
              const bytes = new Uint8Array(buf);
              let binary = '';
              const chunk = 0x8000;
              for (let i = 0; i < bytes.length; i += chunk) {
                binary += String.fromCharCode.apply(
                    null, bytes.subarray(i, i + chunk));
              }
              return { ok: true, status: res.status, body: btoa(binary) };
            } catch (e) {
              return { ok: false, status: 0, body: String(e) };
            }
          ''',
          arguments: {'url': url.toString()},
        )
        .timeout(timeout);

    final value = result?.value;
    if (value is! Map || value['ok'] != true) {
      throw WebViewFetchException(
          (value is Map ? (value['status'] as num?)?.toInt() : 0) ?? 0,
          value is Map ? '${value['body']}' : '取图失败');
    }
    return base64Decode('${value['body']}');
  }

  static const _imageCacheLimit = 400;
  final _imageCache = <String, Uint8List>{};
  final _imageInFlight = <String, Future<Uint8List>>{};

  /// Drops the cached WebView for an origin, e.g. after credentials change.
  Future<void> reset(Uri origin) async {
    final keys = _sessions.keys.where((k) => k.startsWith('${origin.origin}|')).toList();
    for (final k in keys) {
      await _sessions.remove(k)?.dispose();
    }
    _imageCache.clear();
  }
}

class WebViewFetchException implements Exception {
  WebViewFetchException(this.status, this.body);
  final int status;
  final String body;

  bool get isChallenge =>
      status == 403 || status == 503 || body.contains('Just a moment');

  @override
  String toString() => '$status: $body';
}

class _Session {
  _Session(this.origin, this.userAgent);

  final Uri origin;
  final String userAgent;
  final _readyCompleter = Completer<void>();

  late final HeadlessInAppWebView _webView;
  late final InAppWebViewController controller;

  /// What the document itself was answered with, once there is an answer.
  int? _documentStatus;

  Future<void> get ready => _readyCompleter.future;

  Future<void> start() async {
    _webView = HeadlessInAppWebView(
      // Requests only need a page on the right origin to run from. The home
      // page is the whole forum app: it keeps a message-bus poll open, counts
      // every new topic into the title and grows with them for as long as the
      // app runs. A day of that held a WebContent process at 80% CPU and
      // half a gigabyte. robots.txt is a few hundred bytes of text with no
      // script, and bot protection leaves it alone by convention.
      initialUrlRequest:
          URLRequest(url: WebUri(origin.resolve(kDocumentPath).toString())),
      // Nothing is displayed. The page is still put into the window, which is
      // what keeps WebKit running its script, but it need not be window-sized.
      initialSize: const Size(1, 1),
      initialSettings: InAppWebViewSettings(
        userAgent: userAgent,
        javaScriptEnabled: true,
        sharedCookiesEnabled: true,
        isElementFullscreenEnabled: false,
      ),
      onWebViewCreated: (c) => controller = c,
      onReceivedHttpError: (c, request, response) {
        if (request.isForMainFrame ?? true) {
          _documentStatus = response.statusCode;
        }
      },
      onLoadStop: (c, url) async {
        if (_readyCompleter.isCompleted) return;
        final title = await c.getTitle();
        if (_readyCompleter.isCompleted) return;
        final refused = documentRefusal(_documentStatus, title);
        if (refused != null) {
          _readyCompleter.completeError(refused);
        } else {
          _readyCompleter.complete();
        }
      },
      onReceivedError: (c, request, error) {
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.completeError(
              WebViewFetchException(0, error.description));
        }
      },
    );
    await _webView.run();
    try {
      await _readyCompleter.future.timeout(
        const Duration(seconds: 40),
        onTimeout: () => throw WebViewFetchException(0, '打开站点超时'),
      );
    } catch (_) {
      // Not left behind: a challenge page runs a script of its own until it
      // is closed, and nothing would ever close this one.
      await dispose();
      rethrow;
    }
  }

  Future<void> dispose() async {
    await _webView.dispose();
  }
}

/// The page every hidden WebView opens: see [_Session.start].
@visibleForTesting
const kDocumentPath = '/robots.txt';

/// Why the page requests are run from cannot be used, or null when it can.
///
/// Only a challenge counts. Any other answer is still a document on the
/// origin, and a same-origin `fetch` works from it all the same. A challenge
/// is reported the way the requests themselves would have reported it — as
/// the [WebViewFetchException] whose [WebViewFetchException.isChallenge] every
/// caller already turns into "go through the check again" — and it has to be
/// reported here, because the page it leaves open is not one to run anything
/// from: its script can navigate away underneath a request at any moment.
@visibleForTesting
WebViewFetchException? documentRefusal(int? status, String? title) {
  final answer = WebViewFetchException(status ?? 200, title ?? '');
  return answer.isChallenge ? answer : null;
}
