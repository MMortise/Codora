import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/forum_source.dart';

/// One way to put a remote image on screen for every site.
///
/// Most sites load fine with a plain network request. A site read through a
/// proxy, or one whose images sit behind the same protection as its API, says
/// so in its [SiteImages]; nothing else about the call site changes.
class SiteImage extends StatefulWidget {
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
  State<SiteImage> createState() => _SiteImageState();
}

class _SiteImageState extends State<SiteImage> {
  Future<Uint8List>? _future;
  late Uri _target;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant SiteImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.images != widget.images) _start();
  }

  void _start() {
    _target = widget.images.url(widget.url);
    _future = widget.images.loader?.call(_target);
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) {
      return Image.network(
        _target.toString(),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        // Until the first frame decodes, show the fallback rather than a hole
        // in the layout.
        frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
            wasSynchronouslyLoaded || frame != null ? child : widget.fallback,
        errorBuilder: (_, _, _) => widget.fallback,
      );
    }
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData) {
          return Image.memory(
            snap.data!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => widget.fallback,
          );
        }
        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: widget.fallback,
        );
      },
    );
  }
}

/// Builds the right [ImageProvider] for [url], honouring a site's loader.
///
/// The viewer needs a provider rather than a widget so it can read the
/// picture's real dimensions before deciding how to lay it out.
Future<ImageProvider> resolveImageProvider(
  Uri url, {
  SiteImages images = SiteImages.plain,
}) async {
  final target = images.url(url);
  final bytes = images.loader?.call(target);
  if (bytes != null) return MemoryImage(await bytes);
  return NetworkImage(target.toString());
}
