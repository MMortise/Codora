import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../core/forum_source.dart';
import 'site_image.dart';

/// Square-ish avatar with an initial fallback. Same shape family as the rail
/// blocks and section blocks, so faces sit in the grid rather than float.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.url,
    required this.name,
    this.size = 32,
    this.images = SiteImages.plain,
  });

  final String? url;
  final String name;
  final double size;
  final SiteImages images;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: p.raised,
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
            fontSize: size * 0.44,
            fontWeight: FontWeight.w600,
            height: 1,
            color: p.inkMuted),
      ),
    );
    final parsed = (url == null || url!.isEmpty) ? null : Uri.tryParse(url!);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: parsed == null
          ? fallback
          : SiteImage(
              url: parsed,
              width: size,
              height: size,
              fit: BoxFit.cover,
              images: images,
              fallback: fallback,
            ),
    );
  }
}
