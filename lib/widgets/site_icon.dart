import 'package:flutter/material.dart';

import '../app_theme.dart';

/// A forum's logo at a fixed size, with its letters as a fallback.
///
/// The three logos do not share a silhouette: two carry their own light
/// backplate, the third is a bare mark on transparency. So selection is never
/// expressed through the logo itself, only through the surface behind it.
class SiteIcon extends StatelessWidget {
  const SiteIcon({
    super.key,
    required this.asset,
    required this.glyph,
    this.size = 24,
    this.dimmed = false,
  });

  final String asset;

  /// Drawn if the image cannot be decoded.
  final String glyph;
  final double size;

  /// Slightly held back when the site is not the current one.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: size,
      height: size,
      child: Opacity(
        opacity: dimmed ? 0.78 : 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.25),
          child: Image.asset(
            asset,
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => Center(
              child: Text(
                glyph,
                style: TextStyle(
                  fontSize: size * (glyph.length > 1 ? 0.38 : 0.5),
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: p.inkMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
