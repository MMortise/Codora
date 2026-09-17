import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:html/dom.dart' as dom;
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../core/forum_source.dart';
import '../core/models.dart';
import 'post_image.dart';

/// Renders a post body, whatever the site wrote it in.
///
/// The two renderers are an implementation detail: links, images and type
/// scale are decided here once, so a Markdown post and an HTML post look like
/// the same app.
class PostBody extends StatelessWidget {
  const PostBody({
    super.key,
    required this.content,
    required this.format,
    this.baseUrl,
    this.onTopicLink,
    this.images = SiteImages.plain,
    this.fontSize = 15,
  });

  final String content;
  final BodyFormat format;
  final Uri? baseUrl;

  /// Return true if the link was handled in-app.
  final bool Function(Uri uri)? onTopicLink;
  final SiteImages images;
  final double fontSize;

  Uri _resolve(Uri uri) =>
      uri.hasScheme ? uri : (baseUrl?.resolveUri(uri) ?? uri);

  /// The original behind a `<a class="lightbox">` wrapper, if there is one.
  Uri? _lightboxTarget(dom.Element img) {
    for (var node = img.parent; node != null; node = node.parent) {
      if (node.localName != 'a') continue;
      final href = node.attributes['href'];
      if (href == null || href.isEmpty) return null;
      final uri = Uri.tryParse(href);
      return uri == null ? null : _resolve(uri);
    }
    return null;
  }

  Future<bool> _openLink(String? raw) async {
    if (raw == null || raw.isEmpty) return false;
    final uri = Uri.tryParse(raw);
    if (uri == null) return false;
    final resolved = _resolve(uri);
    if (onTopicLink?.call(resolved) == true) return true;
    return launchUrl(resolved, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return switch (format) {
      BodyFormat.html => _HtmlBody(parent: this),
      BodyFormat.markdown => _MarkdownBody(parent: this),
    };
  }
}

class _HtmlBody extends StatelessWidget {
  const _HtmlBody({required this.parent});
  final PostBody parent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    String hex(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

    return HtmlWidget(
      parent.content.isEmpty ? '<p></p>' : parent.content,
      baseUrl: parent.baseUrl,
      textStyle: TextStyle(fontSize: parent.fontSize, height: 1.65, color: p.ink),
      onTapUrl: parent._openLink,
      customStylesBuilder: (el) {
        // Discourse hangs a caption off every lightbox image: file name, pixel
        // dimensions and size. `display: none` on the wrapper does not cascade
        // to its children here, so each part is named.
        const lightboxCaption = {'meta', 'filename', 'informations'};
        if (el.classes.any(lightboxCaption.contains)) {
          return {'display': 'none'};
        }
        switch (el.localName) {
          case 'pre':
            return {
              'background-color': hex(p.raised),
              'padding': '12px 14px',
              'margin': '10px 0',
              'font-size': '12.5px',
            };
          case 'code':
            return {'background-color': hex(p.raised), 'font-size': '12.5px'};
          case 'blockquote':
            return {
              'border-left': '3px solid ${hex(p.line)}',
              'margin': '8px 0',
              'padding': '0 0 0 12px',
              'color': hex(p.inkMuted),
            };
          case 'a':
            return {'color': hex(p.accent), 'text-decoration': 'none'};
          case 'img':
            return {'max-width': '100%'};
          case 'table':
            return {'border': '1px solid ${hex(p.line)}'};
          case 'th':
          case 'td':
            return {
              'border': '1px solid ${hex(p.line)}',
              'padding': '4px 8px',
            };
        }
        return null;
      },
      // Every picture goes through PostImage so it gets the same corner
      // radius and placeholder as one written in Markdown.
      customWidgetBuilder: (el) {
        if (el.localName != 'img') return null;
        final src = el.attributes['src'];
        if (src == null || src.isEmpty) return null;
        final uri = Uri.tryParse(src);
        if (uri == null) return null;
        return PostImage(
          url: parent._resolve(uri),
          // Discourse shows a resized copy and links the original from the
          // enclosing lightbox anchor; that is what the viewer should open.
          fullUrl: parent._lightboxTarget(el),
          alt: el.attributes['alt'],
          images: parent.images,
          rounded: !el.className.contains('emoji'),
        );
      },
    );
  }
}

class _MarkdownBody extends StatelessWidget {
  const _MarkdownBody({required this.parent});
  final PostBody parent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final size = parent.fontSize;
    final body = TextStyle(fontSize: size, height: 1.65, color: p.ink);
    final mono = TextStyle(
      fontFamily: 'Menlo',
      fontFamilyFallback: const ['Consolas', 'monospace'],
      fontSize: size - 2.5,
      height: 1.5,
      color: p.ink,
    );

    return MarkdownBody(
      data: parent.content,
      selectable: false,
      onTapLink: (text, href, title) => parent._openLink(href),
      // The markdown package wires a tap recognizer to links but never sets a
      // cursor, so they look like plain text on hover. The HTML renderer does
      // this itself; this brings the two in line.
      builders: {'a': _MarkdownLink(parent)},
      imageBuilder: (uri, title, alt) => PostImage(
        url: parent._resolve(uri),
        alt: alt,
        images: parent.images,
      ),
      styleSheet: MarkdownStyleSheet(
        p: body,
        a: TextStyle(fontSize: size, color: p.accent),
        em: body.copyWith(fontStyle: FontStyle.italic),
        strong: body.copyWith(fontWeight: FontWeight.w600),
        del: body.copyWith(decoration: TextDecoration.lineThrough),
        h1: TextStyle(
            fontSize: size + 7, height: 1.3, fontWeight: FontWeight.w700, color: p.ink),
        h2: TextStyle(
            fontSize: size + 4, height: 1.3, fontWeight: FontWeight.w700, color: p.ink),
        h3: TextStyle(
            fontSize: size + 2, height: 1.35, fontWeight: FontWeight.w600, color: p.ink),
        h4: TextStyle(
            fontSize: size + 1, height: 1.4, fontWeight: FontWeight.w600, color: p.ink),
        h5: body.copyWith(fontWeight: FontWeight.w600),
        h6: body.copyWith(fontWeight: FontWeight.w600, color: p.inkMuted),
        h1Padding: const EdgeInsets.only(top: 18, bottom: 4),
        h2Padding: const EdgeInsets.only(top: 16, bottom: 4),
        h3Padding: const EdgeInsets.only(top: 14, bottom: 2),
        h4Padding: const EdgeInsets.only(top: 12, bottom: 2),
        pPadding: const EdgeInsets.symmetric(vertical: 5),
        listBullet: body,
        listIndent: 22,
        code: mono.copyWith(backgroundColor: p.raised),
        codeblockPadding: const EdgeInsets.all(14),
        codeblockDecoration: BoxDecoration(
          color: p.raised,
          borderRadius: BorderRadius.circular(Radii.image),
        ),
        blockquote: body.copyWith(color: p.inkMuted),
        blockquotePadding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: p.line, width: 3)),
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.line)),
        ),
        tableHead: body.copyWith(fontWeight: FontWeight.w600),
        tableBody: body.copyWith(fontSize: size - 1),
        tableBorder: TableBorder.all(color: p.line, width: 1),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        blockSpacing: 10,
      ),
    );
  }
}

/// Draws a markdown link so it announces itself on hover.
///
/// Inline content in this package is already a sequence of separate text
/// widgets, so replacing one with another widget does not change how a long
/// link wraps.
class _MarkdownLink extends MarkdownElementBuilder {
  _MarkdownLink(this.parent);

  final PostBody parent;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text = element.textContent;
    if (text.isEmpty) return null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => parent._openLink(element.attributes['href']),
        child: Text(
          text,
          style: preferredStyle ?? parentStyle,
        ),
      ),
    );
  }
}
