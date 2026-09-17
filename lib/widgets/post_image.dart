import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'image_viewer.dart';
import 'site_image.dart';

/// The single way a picture appears inside a post body, so the HTML renderer
/// and the Markdown renderer produce identical results: same corner radius,
/// same loader, same placeholder when it cannot be reached.
class PostImage extends StatelessWidget {
  const PostImage({
    super.key,
    required this.url,
    this.alt,
    this.headers,
    this.loader,
    this.rounded = true,
    this.fullUrl,
  });

  final Uri url;
  final String? alt;
  final Map<String, String>? headers;
  final Future<Uint8List>? Function(Uri url)? loader;

  /// Inline emoji keep their own shape; clipping a 20px glyph would cut it.
  /// They are also not worth opening full screen.
  final bool rounded;

  /// Full-size version, when the site offers one. Discourse links the original
  /// behind its lightbox while showing a smaller copy inline.
  final Uri? fullUrl;

  @override
  Widget build(BuildContext context) {
    final image = SiteImage(
      url: url,
      headers: headers,
      loader: loader,
      fallback: BrokenImage(alt: alt),
    );
    if (!rounded) return image;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      // Align turns the pane's fixed width into an upper bound. Without it a
      // picture is forced to fill the pane: a small one is blown up and
      // blurred, and a large one is laid out at its original pixel size,
      // spilling past the edge so its rounded corners fall off screen and its
      // scaled height leaves a tall gap. With it, a picture keeps its own size
      // until it would exceed the pane, then shrinks to fit.
      child: Align(
        alignment: Alignment.centerLeft,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => showImageViewer(
              context,
              url: fullUrl ?? url,
              alt: alt,
              headers: headers,
              loader: loader,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.image),
              child: image,
            ),
          ),
        ),
      ),
    );
  }
}

/// Quiet stand-in for an image that would not load, so a dead link never
/// becomes the loudest thing on the page.
class BrokenImage extends StatelessWidget {
  const BrokenImage({super.key, this.alt});
  final String? alt;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = (alt == null || alt!.trim().isEmpty) ? '图片没能加载' : alt!.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: BorderRadius.circular(Radii.image),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported_outlined, size: 15, color: p.inkFaint),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: p.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}
