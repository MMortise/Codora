import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_theme.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../widgets/chrome.dart';
import 'providers.dart';

/// Opens linux.do in an embedded browser so the user can pass the Cloudflare
/// challenge (and optionally log in). Cookies are then copied to the HTTP
/// client together with the exact User-Agent the WebView used.
class LinuxDoAuthPage extends ConsumerStatefulWidget {
  const LinuxDoAuthPage({super.key});

  @override
  ConsumerState<LinuxDoAuthPage> createState() => _LinuxDoAuthPageState();
}

class _LinuxDoAuthPageState extends ConsumerState<LinuxDoAuthPage> {
  InAppWebViewController? _controller;
  bool _cleared = false;
  bool _loggedIn = false;
  bool _saving = false;
  String _url = 'https://linux.do/';
  List<String> _cookieNames = const [];

  Future<void> _checkCookies() async {
    final cookies = await CookieManager.instance()
        .getCookies(url: WebUri('https://linux.do/'));
    if (!mounted) return;
    setState(() {
      _cookieNames = cookies.map((c) => c.name).toList()..sort();
      _cleared = cookies.any((c) => c.name == 'cf_clearance');
      _loggedIn = cookies.any((c) => c.name == '_t');
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final cookies = await CookieManager.instance()
        .getCookies(url: WebUri('https://linux.do/'));
    final header = cookies.map((c) => '${c.name}=${c.value}').join('; ');
    await ref.read(settingsProvider.notifier).patch((s) =>
        s.copyWith(linuxdoCookie: header, linuxdoUserAgent: kDesktopUserAgent));
    ref.invalidate(sectionsProvider(SiteId.linuxdo));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final status = _loggedIn
        ? '已登录，可以回去看帖了'
        : _cleared
            ? '验证通过。不登录也能读公开内容，登录后能看到更多板块'
            : '在下面完成人机验证，需要的话顺便登录';
    return Scaffold(
      backgroundColor: p.canvas,
      appBar: AppBar(
        backgroundColor: p.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text('linux.do 验证',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink)),
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
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('保存并返回'),
            ),
          ),
        ],
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: p.panel,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(_cleared ? Icons.check_circle_rounded : Icons.shield_outlined,
                size: 17, color: _cleared ? p.mint : p.inkMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(status, style: TextStyle(fontSize: 13, color: p.ink)),
                Text(
                  _cookieNames.isEmpty
                      ? '还没拿到 Cookie'
                      : '已拿到 ${_cookieNames.length} 个 Cookie',
                  style: TextStyle(color: p.inkFaint, fontSize: 11.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 240,
              child: Text(_url,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: p.inkFaint, fontSize: 11.5),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri('https://linux.do/')),
            initialSettings: InAppWebViewSettings(
              userAgent: kDesktopUserAgent,
              javaScriptEnabled: true,
              sharedCookiesEnabled: true,
            ),
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
}
