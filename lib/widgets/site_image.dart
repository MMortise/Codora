import 'dart:typed_data';

import 'package:flutter/material.dart';

/// One way to put a remote image on screen for every site.
///
/// Most sites load fine with a plain network request. A site whose images sit
/// behind the same protection as its API supplies a [loader] instead, and
/// nothing else about the call site changes.
class SiteImage extends StatefulWidget {
  const SiteImage({
    super.key,
    required this.url,
    this.headers,
    this.loader,
    this.width,
    this.height,
    this.fit,
    required this.fallback,
  });

  final Uri url;
  final Map<String, String>? headers;
  final Future<Uint8List>? Function(Uri url)? loader;
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

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant SiteImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.loader != widget.loader) _start();
  }

  void _start() {
    _future = widget.loader?.call(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) {
      return Image.network(
        widget.url.toString(),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        headers: widget.headers,
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
  Map<String, String>? headers,
  Future<Uint8List>? Function(Uri url)? loader,
}) async {
  final bytes = loader?.call(url);
  if (bytes != null) return MemoryImage(await bytes);
  return NetworkImage(url.toString(), headers: headers);
}
