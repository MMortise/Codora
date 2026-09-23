import 'package:html/parser.dart' as html_parser;

String relativeTime(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return '刚刚';
  if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
  if (d.inHours < 24) return '${d.inHours} 小时前';
  if (d.inDays < 30) return '${d.inDays} 天前';
  if (d.inDays < 365) return '${(d.inDays / 30).floor()} 个月前';
  return '${(d.inDays / 365).floor()} 年前';
}

/// Absolute timestamp down to the second, for the tooltip behind a relative
/// time like "11 分钟前".
String fullTime(DateTime? t) {
  if (t == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// Collapse HTML to a single-line plain-text preview.
String htmlToPreview(String? html, {int max = 160}) {
  if (html == null || html.isEmpty) return '';
  final text = html_parser.parse(html).body?.text ?? '';
  final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return oneLine.length > max ? '${oneLine.substring(0, max)}…' : oneLine;
}

/// What to put in front of a reader when something threw.
///
/// `Exception.toString()` prefixes the class name, which means nothing to
/// anyone: the sources write the sentence they want shown, and it is the
/// sentence that should appear.
String errorText(Object error) => '$error'.replaceFirst('Exception: ', '');

/// Whether a `Cookie:` header carries a cookie called [name].
///
/// Searching the header for `'$name='` is close enough to work until it is
/// not: `visit_t=…` contains `_t=`, which would report a reader who has just
/// signed out as still signed in. Names are compared whole.
bool cookieHeaderHas(String header, String name) =>
    header.split(';').any((pair) => pair.trim().split('=').first == name);

/// The kinds of picture worth offering a forum, and what each one is.
///
/// A site decides what it takes by the extension, but the browser writes a
/// content type onto every file it sends in a form — and a PNG announced as
/// `application/octet-stream` is a PNG a forum can refuse.
const kPictureTypes = <String, String>{
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'avif': 'image/avif',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'bmp': 'image/bmp',
  'svg': 'image/svg+xml',
};

/// What [filename] is, as far as handing it to a site is concerned.
String pictureContentType(String filename) {
  final dot = filename.lastIndexOf('.');
  final kind = dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
  return kPictureTypes[kind] ?? 'application/octet-stream';
}

String compactCount(int? n) {
  if (n == null) return '';
  if (n < 1000) return '$n';
  if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '${(n / 10000).toStringAsFixed(1)}w';
}
