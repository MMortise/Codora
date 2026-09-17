import 'package:flutter/material.dart';

import '../core/forum_source.dart';
import 'cached_image.dart';

/// One way to put a remote image on screen for every site.
///
/// Most sites load fine with a plain network request. A site read through a
/// proxy, or one whose images sit behind the same protection as its API, says
/// so in its [SiteImages]; nothing else about the call site changes.
class SiteImage extends StatelessWidget {
  const SiteImage({
    super.key,
    required this.url,
    this.images = SiteImages.plain,
    this.width,
    this.height,
    this.fit,
    required this.fallback,
  });

  /// The address the site published. What is actually requested is this put
  /// through [images].
  final Uri url;
  final SiteImages images;
  final double? width;
  final double? height;
  final BoxFit? fit;

  /// Shown while loading and when the image cannot be reached.
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    // One path for every site now. Fetching bytes by hand — which is what a
    // proxied or challenged site needs — used to mean giving up both caches:
    // a fresh request per mount, and nothing kept across a restart. Handing
    // the job to an ImageProvider gets both back, and the sites that need
    // nothing special ride along. It is also what leaves nothing for this
    // widget to remember: the address is worked out in build, and a new one
    // is simply a different key.
    return Image(
      image: CachedImage(images.url(url), loader: images.loader),
      width: width,
      height: height,
      fit: fit,
      gaplessPlayback: true,
      // Until the first frame decodes, show the fallback rather than a hole
      // in the layout.
      frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
          wasSynchronouslyLoaded || frame != null ? child : fallback,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// Builds the right [ImageProvider] for [url], honouring a site's loader.
///
/// The viewer needs a provider rather than a widget so it can read the
/// picture's real dimensions before deciding how to lay it out.
ImageProvider resolveImageProvider(
  Uri url, {
  SiteImages images = SiteImages.plain,
}) =>
    CachedImage(images.url(url), loader: images.loader);
