import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Crossfades whatever replaces what was here, with a small upward drift so
/// the new content reads as arriving rather than blinking into place.
///
/// [swapKey] is what identifies "a different thing": a board id, a post id, a
/// site name. When it is unchanged the child rebuilds without any animation.
class Swap extends StatelessWidget {
  const Swap({
    super.key,
    required this.swapKey,
    required this.child,
    this.drift = Motion.drift,
    this.alignment = Alignment.topCenter,
  });

  final Object swapKey;
  final Widget child;

  /// Vertical travel of the incoming content. Zero keeps it to a plain fade,
  /// which suits small things like a label.
  final double drift;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.swap,
      switchInCurve: Motion.curve,
      switchOutCurve: Motion.curve,
      // Outgoing content leaves immediately so two lists never overlap and
      // smear; only the arrival is animated.
      layoutBuilder: (current, previous) => Stack(
        alignment: alignment,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) {
        final fade = FadeTransition(opacity: animation, child: child);
        if (drift == 0) return fade;
        return SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0, drift / 100),
            end: Offset.zero,
          ).animate(animation),
          child: fade,
        );
      },
      child: KeyedSubtree(key: ValueKey(swapKey), child: child),
    );
  }
}
