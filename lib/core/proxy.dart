/// A proxy the reader puts in front of a site.
///
/// Two kinds, told apart by whether the address says where the target goes:
///
///  * a **tunnel** — `172.16.12.90:27006`, or `http://127.0.0.1:7890`. This is
///    what `HTTP_PROXY`, `curl -x` and a browser's proxy setting all mean, and
///    what Clash, v2ray or a company gateway hands you. Requests are sent
///    through it (HTTPS by `CONNECT`) and the site sees an ordinary request.
///  * a **rewriter** — an address naming where the target goes, with `{url}`
///    or `{encoded_url}`: `https://p.example.com/{url}`. That is a service
///    which fetches the target for you, so its address is folded into the
///    request itself. A Cloudflare Worker in front of a site works this way.
///
/// A bare host and port is by far the common case, so it is the default
/// reading; a rewriter says so with a placeholder.
sealed class SiteProxy {
  const SiteProxy();

  /// Null for a blank or unusable address, so a half-typed value leaves the
  /// site reachable instead of breaking every request.
  static SiteProxy? parse(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (t.contains('{url}') || t.contains('{encoded_url}')) {
      return ProxyRewrite(t);
    }
    // A proxy is usually written without one, so a missing scheme is filled
    // in rather than rejected.
    final withScheme = t.contains('://') ? t : 'http://$t';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty || !uri.hasPort) return null;
    // Dart tunnels over http(s) only; a SOCKS address would need a different
    // client, and quietly treating it as http would fail in a way nobody
    // could read.
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return ProxyTunnel('${uri.host}:${uri.port}');
  }
}

/// A proxy requests are tunnelled through, addressed as `host:port`.
class ProxyTunnel extends SiteProxy {
  const ProxyTunnel(this.authority);

  /// In the form Dart's `HttpClient.findProxy` wants.
  final String authority;

  String get proxyString => 'PROXY $authority';

  @override
  bool operator ==(Object other) =>
      other is ProxyTunnel && other.authority == authority;

  @override
  int get hashCode => authority.hashCode;
}

/// A proxy that fetches the target for you, given its address.
class ProxyRewrite extends SiteProxy {
  const ProxyRewrite(this.template);

  final String template;

  Uri apply(Uri target) => Uri.parse(applyTo(target.toString()));

  // `{` and `}` come back percent-encoded, so substituting the escaped form
  // first cannot produce a second placeholder for the plain one to find.
  String applyTo(String target) => template
      .replaceAll('{encoded_url}', Uri.encodeComponent(target))
      .replaceAll('{url}', target);

  @override
  bool operator ==(Object other) =>
      other is ProxyRewrite && other.template == template;

  @override
  int get hashCode => template.hashCode;
}
