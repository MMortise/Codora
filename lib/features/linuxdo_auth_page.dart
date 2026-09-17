import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_theme.dart';
import '../core/linuxdo_session.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../widgets/chrome.dart';
import 'providers.dart';

/// Tells every page in this browser that it has no passkey to offer.
///
/// A passkey needs the platform's own prompt, and WKWebView only raises one
/// for a site the *app* has been associated with — which linux.do and its
/// sign-in providers obviously have not. The damaging part is not that it
/// fails: it is that `PublicKeyCredential` exists, so the page believes
/// passkeys work, calls for one, and waits behind a spinner for a prompt that
/// is never coming. There is no error and no way back.
///
/// Removing the feature detection turns that dead end into an ordinary
/// branch: the page sees a browser without passkeys and offers a password or
/// another method, which is what actually works here. `navigator.credentials`
/// is left in place for everything else it does — only a request carrying a
/// `publicKey` is turned away, and with a real WebAuthn error rather than
/// silence.
final _noPasskeys = UserScript(
  source: """
    (() => {
      try { delete window.PublicKeyCredential; } catch (e) {}
      const creds = navigator.credentials;
      if (!creds) return;
      const refuse = () => Promise.reject(new DOMException(
          'Passkeys are unavailable in this view', 'NotAllowedError'));
      for (const name of ['get', 'create']) {
        const original = creds[name] && creds[name].bind(creds);
        creds[name] = (options) =>
            options && options.publicKey ? refuse()
            : original ? original(options) : refuse();
      }
    })();
  """,
  injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  forMainFrameOnly: false,
);

/// Opens linux.do in an embedded browser: to pass the Cloudflare challenge,
/// to sign in, or both. Whatever the browser ends up holding is copied to the
/// HTTP client together with the exact User-Agent it used.
class LinuxDoAuthPage extends ConsumerStatefulWidget {
  const LinuxDoAuthPage({super.key, this.signIn = false});

  /// Opens the sign-in form rather than the front page. The challenge stands
  /// in front of both, so this only decides where the reader lands once it is
  /// out of the way.
  final bool signIn;

  @override
  ConsumerState<LinuxDoAuthPage> createState() => _LinuxDoAuthPageState();
}

class _LinuxDoAuthPageState extends ConsumerState<LinuxDoAuthPage> {
  InAppWebViewController? _controller;
  bool _cleared = false;
  bool _loggedIn = false;
  bool _saving = false;

  /// Set once the sign-in has been saved and this page is on its way out, so
  /// a redirect arriving behind it cannot start a second save.
  bool _finishing = false;

  String _url = '';
  List<String> _cookieNames = const [];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        backgroundColor: p.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.signIn ? '登录 linux.do' : 'linux.do 验证',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: p.ink)),
        actions: [
          QuietIconButton(
            icon: Icons.refresh_rounded,
            tooltip: '重新加载',
            onPressed: () => _controller?.reload(),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _cookieNames.isNotEmpty && !_saving ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('保存并返回'),
            ),
          ),
        ],
      ),
      body: Column(children: [
        _Status(
          cleared: _cleared,
          loggedIn: _loggedIn,
          cookies: _cookieNames.length,
          url: _url,
        ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_landing)),
            initialSettings: InAppWebViewSettings(
              userAgent: kDesktopUserAgent,
              javaScriptEnabled: true,
              sharedCookiesEnabled: true,
            ),
            initialUserScripts: UnmodifiableListView([_noPasskeys]),
            onWebViewCreated: (c) => _controller = c,
            onLoadStop: (c, url) async {
              if (url != null) setState(() => _url = url.toString());
              await _checkCookies();
            },
            onUpdateVisitedHistory: (c, url, _) {
              if (url != null) setState(() => _url = url.toString());
            },
          ),
        ),
      ]),
    );
  }

  String get _landing =>
      widget.signIn ? '$linuxdoOrigin/login' : '$linuxdoOrigin/';

  Future<void> _checkCookies() async {
    final cookies =
        await CookieManager.instance().getCookies(url: WebUri('$linuxdoOrigin/'));
    if (!mounted) return;
    // Only the sign-in counts. `_forum_session` arrives with the very first
    // page load, signed in or not, so reading it as a sign-in made this page
    // save and close itself the instant it opened.
    final loggedIn = cookies.any((c) => c.name == kLinuxdoSignIn);
    setState(() {
      _cookieNames = cookies.map((c) => c.name).toList()..sort();
      _cleared = cookies.any((c) => c.name == kLinuxdoClearance);
      _loggedIn = loggedIn;
    });
    // Signing in ends on a redirect back to the forum, which is a poor moment
    // to ask someone to notice a button in the corner. The cookie arriving is
    // the whole point of being here, so it finishes the job itself.
    if (loggedIn && !_finishing) {
      _finishing = true;
      await _save();
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final cookies =
        await CookieManager.instance().getCookies(url: WebUri('$linuxdoOrigin/'));
    final header = cookies.map((c) => '${c.name}=${c.value}').join('; ');
    await ref.read(settingsProvider.notifier).patch((s) =>
        s.copyWith(linuxdoCookie: header, linuxdoUserAgent: kDesktopUserAgent));
    ref.invalidate(sectionsProvider(SiteId.linuxdo));
    if (mounted) Navigator.of(context).pop(true);
  }
}

/// The strip above the browser: which of the two gates is behind you, and
/// what is left to do.
class _Status extends StatelessWidget {
  const _Status({
    required this.cleared,
    required this.loggedIn,
    required this.cookies,
    required this.url,
  });

  final bool cleared;
  final bool loggedIn;
  final int cookies;
  final String url;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, tone, line) = loggedIn
        ? (Icons.check_circle_rounded, p.mint, '已登录，正在保存并返回')
        : cleared
            ? (
                Icons.person_outline_rounded,
                p.inkMuted,
                '验证通过。不登录也能读公开内容；要看更多板块就在下面登录'
              )
            : (
                Icons.shield_outlined,
                p.inkMuted,
                '先完成人机验证，通过后这里会变成登录'
              );

    return Container(
      width: double.infinity,
      color: p.panel,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Icon(icon, size: 17, color: tone),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(line, style: TextStyle(fontSize: 13, color: p.ink)),
            Text(
              cookies == 0 ? '还没拿到 Cookie' : '已拿到 $cookies 个 Cookie',
              style: TextStyle(color: p.inkFaint, fontSize: 11.5),
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 240,
          child: Text(url,
              textAlign: TextAlign.right,
              style: TextStyle(color: p.inkFaint, fontSize: 11.5),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}
