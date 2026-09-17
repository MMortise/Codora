/// A reverse proxy the reader puts in front of a site.
///
/// Two shapes are accepted, because both are what people already run:
///
///  * a prefix the target address is appended to —
///    `https://p.example.com/` becomes
///    `https://p.example.com/https://www.v2ex.com/api/topics/hot.json`;
///  * a template saying where the target goes, `{url}` for the address as
///    written and `{encoded_url}` for a percent-encoded one, which is what a
///    proxy taking its target as a query parameter needs.
///
/// A prefix is just the template `<prefix>/{url}`, so [parse] rewrites it into
/// one and every address afterwards is handled the same way.
class UrlProxy {
  const UrlProxy._(this.template);

  /// Null for a blank or not-yet-finished address, so a half-typed value
  /// leaves the site reachable instead of breaking every request.
  static UrlProxy? parse(String raw) {
    var t = raw.trim();
    if (!t.startsWith('http://') && !t.startsWith('https://')) return null;
    if (Uri.tryParse(t) == null) return null;
    if (!t.contains('{url}') && !t.contains('{encoded_url}')) {
      t = t.endsWith('/') ? '$t{url}' : '$t/{url}';
    }
    return UrlProxy._(t);
  }

  final String template;

  Uri apply(Uri target) => Uri.parse(applyTo(target.toString()));

  // `{` and `}` come back percent-encoded, so substituting the escaped form
  // first cannot produce a second placeholder for the plain one to find.
  String applyTo(String target) => template
      .replaceAll('{encoded_url}', Uri.encodeComponent(target))
      .replaceAll('{url}', target);
}
