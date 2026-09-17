import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import 'post_image.dart';
import 'site_image.dart';

/// A picture taller than this much of its width is read by scrolling, not by
/// shrinking it to fit. Screenshots of chat logs and articles land here.
const _tallRatio = 2.2;

/// Opens [url] full screen over a dimmed backdrop.
///
/// Click the backdrop, press Escape, or use the close button to leave.
Future<void> showImageViewer(
  BuildContext context, {
  required Uri url,
  String? alt,
  Map<String, String>? headers,
  Future<Uint8List>? Function(Uri url)? loader,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭图片',
    barrierColor: Colors.black.withValues(alpha: 0.82),
    transitionDuration: Motion.swap,
    pageBuilder: (context, _, _) =>
        _ImageViewer(url: url, alt: alt, headers: headers, loader: loader),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.curve);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// How the picture is presented once its dimensions are known.
enum ViewerMode {
  /// Whole picture on screen at once, zoom and drag to inspect.
  fit,

  /// Rendered at a readable width and scrolled vertically.
  scroll,
}

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.url, this.alt, this.headers, this.loader});

  final Uri url;
  final String? alt;
  final Map<String, String>? headers;
  final Future<Uint8List>? Function(Uri url)? loader;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  final _transform = TransformationController();
  late Future<ImageProvider> _provider;
  Size? _size;
  ViewerMode? _mode;
  bool _zoomed = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _provider = resolveImageProvider(widget.url,
        headers: widget.headers, loader: widget.loader);
    _measure();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Reads the picture's real dimensions so the layout can be chosen for it.
  Future<void> _measure() async {
    try {
      final provider = await _provider;
      final completer = Completer<Size>();
      final stream = provider.resolve(ImageConfiguration.empty);
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) {
            completer.complete(Size(
                info.image.width.toDouble(), info.image.height.toDouble()));
          }
          stream.removeListener(listener);
        },
        onError: (error, _) {
          if (!completer.isCompleted) completer.completeError(error);
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      final size = await completer.future;
      if (!mounted) return;
      setState(() {
        _size = size;
        _mode ??= size.height / size.width >= _tallRatio
            ? ViewerMode.scroll
            : ViewerMode.fit;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  bool get _isTall =>
      _size != null && _size!.height / _size!.width >= _tallRatio;

  void _setMode(ViewerMode mode) {
    _transform.value = Matrix4.identity();
    setState(() {
      _mode = mode;
      _zoomed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        // Anywhere outside the picture dismisses, same as the backdrop.
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned.fill(child: _buildContent()),
        Positioned(top: 16, right: 16, child: _buildActions(p)),
        if (widget.alt != null && widget.alt!.trim().isNotEmpty)
          Positioned(left: 0, right: 0, bottom: 24, child: _buildCaption()),
      ]),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return const Center(child: BrokenImage());
    }
    if (_size == null || _mode == null) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
        ),
      );
    }
    return switch (_mode!) {
      ViewerMode.fit => _buildFit(),
      ViewerMode.scroll => _buildScroll(),
    };
  }

  Widget _buildFit() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 72, 72, 72),
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 6,
        onInteractionEnd: (_) {
          final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
          if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
        },
        child: Center(child: _image(fit: BoxFit.contain)),
      ),
    );
  }

  /// A tall picture is drawn at a comfortable reading width and scrolled,
  /// which is how the same image behaves on the site it came from.
  Widget _buildScroll() {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.clamp(0.0, 900.0) * 0.62;
      return GestureDetector(
        // Taps land on the backdrop behind, so leaving stays easy.
        onTap: () => Navigator.of(context).maybePop(),
        behavior: HitTestBehavior.translucent,
        child: Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 64),
            child: Center(
              child: GestureDetector(
                onTap: () {},
                child: SizedBox(width: width, child: _image(fit: BoxFit.fitWidth)),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _image({required BoxFit fit}) {
    return FutureBuilder<ImageProvider>(
      future: _provider,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        return Image(
          image: snap.data!,
          fit: fit,
          errorBuilder: (_, _, _) => const BrokenImage(),
        );
      },
    );
  }

  Widget _buildActions(Palette p) {
    return Row(children: [
      if (_size != null && (_isTall || _mode == ViewerMode.scroll))
        _ViewerButton(
          icon: _mode == ViewerMode.scroll
              ? Icons.fit_screen_outlined
              : Icons.height_rounded,
          tooltip: _mode == ViewerMode.scroll ? '整幅查看' : '按长图浏览',
          onPressed: () => _setMode(
              _mode == ViewerMode.scroll ? ViewerMode.fit : ViewerMode.scroll),
        ),
      if (_zoomed)
        _ViewerButton(
          icon: Icons.zoom_out_map_rounded,
          tooltip: '恢复原始大小',
          onPressed: () => _setMode(ViewerMode.fit),
        ),
      _ViewerButton(
        icon: Icons.north_east_rounded,
        tooltip: '在浏览器中打开',
        onPressed: () =>
            launchUrl(widget.url, mode: LaunchMode.externalApplication),
      ),
      _ViewerButton(
        icon: Icons.link_rounded,
        tooltip: '复制图片地址',
        onPressed: () {
          Clipboard.setData(ClipboardData(text: widget.url.toString()));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('图片地址已复制'),
            backgroundColor: p.raised,
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            width: 220,
          ));
        },
      ),
      _ViewerButton(
        icon: Icons.close_rounded,
        tooltip: '关闭',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    ]);
  }

  Widget _buildCaption() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Text(
          widget.alt!.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: Colors.white70),
        ),
      ),
    );
  }
}

class _ViewerButton extends StatelessWidget {
  const _ViewerButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Material(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(Radii.block),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.block),
          onTap: onPressed,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(icon, size: 17, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
