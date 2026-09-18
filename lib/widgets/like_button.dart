import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../core/models.dart';
import '../core/util.dart';
import 'chrome.dart';

/// The likes on a post, and the reader's own among them.
///
/// It turns the moment it is pressed rather than when the forum answers. A
/// like is small and immediately reversible, and a heart that waits on a
/// round trip before it fills reads as a broken one; if the forum refuses,
/// it turns back and says why.
class LikeButton extends StatefulWidget {
  const LikeButton({
    super.key,
    required this.state,
    required this.onLike,
    this.pill = false,
  });

  final LikeState state;

  /// Answers with where the post stands once the forum has it — the count
  /// that comes back is the site's, not this widget's arithmetic. Throws with
  /// what to tell the reader when it is refused.
  final Future<LikeState> Function(bool like) onLike;

  /// Drawn as one of the pills over a post, rather than as small print beside
  /// a reply's name.
  final bool pill;

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> {
  late LikeState _now = widget.state;
  bool _busy = false;

  @override
  void didUpdateWidget(covariant LikeButton old) {
    super.didUpdateWidget(old);
    // The list this sits in is rebuilt from the thread, and a tile scrolled
    // out of sight comes back from it: when that thread has something new to
    // say, it wins over what was pressed here.
    if (old.state.count != widget.state.count ||
        old.state.liked != widget.state.liked) {
      _now = widget.state;
    }
  }

  Future<void> _press() async {
    if (_busy || !_now.open) return;
    final before = _now;
    final wanted = !before.liked;
    setState(() {
      _busy = true;
      _now = LikeState(
        count: (before.count + (wanted ? 1 : -1)).clamp(0, 1 << 30),
        liked: wanted,
        // Taking one back is allowed for a while; adding one is allowed again
        // the moment it has been taken back.
        canLike: wanted ? before.canLike : true,
        canUnlike: wanted,
      );
    });
    try {
      final after = await widget.onLike(wanted);
      if (!mounted) return;
      setState(() {
        _now = after;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _now = before;
        _busy = false;
      });
      final p = context.palette;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorText(e)),
        backgroundColor: p.raised,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Nothing to show and nothing to do: a post nobody has liked and this
    // reader may not — their own, usually.
    if (_now.count == 0 && !_now.open) return const SizedBox.shrink();

    final liked = _now.liked;
    final tone = liked ? p.cream : p.inkFaint;
    final icon = liked ? Icons.favorite_rounded : Icons.favorite_border_rounded;
    final label = _now.count == 0 ? '赞' : '${compactCount(_now.count)} 赞';

    final Widget face = widget.pill
        ? Pill(
            label: label,
            icon: icon,
            tone: liked ? p.cream : null,
            filled: liked,
          )
        : Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: tone),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11.5, color: tone)),
          ]);

    if (!_now.open) return face;
    return Tooltip(
      message: liked ? '取消点赞' : '点赞',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _press,
          behavior: HitTestBehavior.opaque,
          child: face,
        ),
      ),
    );
  }
}
