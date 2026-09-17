import 'dart:async';

import 'package:flutter/material.dart';

/// How long an open panel waits after the pointer leaves.
///
/// The pointer has to cross open space to reach the panel, and one that shut
/// under it on the way would be impossible to get to. It also covers clipping
/// a neighbour on the way out.
const kFlyoutGrace = Duration(milliseconds: 140);

/// A panel that opens to the right of a trigger while the pointer rests on
/// either of them.
///
/// [builder] is handed the hover state of the pair rather than of the trigger
/// alone, so a trigger can stay lit while the panel it opened is being read.
/// [panel] is mounted only while open, which is what keeps anything expensive
/// inside it — a fetch included — from happening until someone looks.
class HoverFlyout extends StatefulWidget {
  const HoverFlyout({super.key, required this.builder, this.panel});

  final Widget Function(BuildContext context, bool hovered) builder;

  /// Null for a trigger with nothing to show. It then behaves as a plain
  /// hover region, which is what lets a caller decide per item.
  final Widget? panel;

  @override
  State<HoverFlyout> createState() => _HoverFlyoutState();
}

class _HoverFlyoutState extends State<HoverFlyout> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  Timer? _leaving;
  bool _hover = false;

  @override
  void didUpdateWidget(covariant HoverFlyout old) {
    super.didUpdateWidget(old);
    // A trigger can lose its panel while open — credentials cleared in
    // settings, say. This build drops the whole overlay from the tree, which
    // takes the panel off screen, but the controller is not told and would
    // spring the next panel open by itself. Resetting it has to wait until
    // the build is over: it refuses to be closed during one.
    if (widget.panel != null || !_portal.isShowing) return;
    _leaving?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.panel == null && _portal.isShowing) _portal.hide();
    });
  }

  @override
  void dispose() {
    _leaving?.cancel();
    super.dispose();
  }

  void _enter() {
    _leaving?.cancel();
    if (!_hover) setState(() => _hover = true);
    if (widget.panel != null && !_portal.isShowing) _portal.show();
  }

  void _exit() {
    _leaving?.cancel();
    _leaving = Timer(kFlyoutGrace, () {
      if (!mounted) return;
      setState(() => _hover = false);
      if (_portal.isShowing) _portal.hide();
    });
  }

  Widget _watched(Widget child) => MouseRegion(
        onEnter: (_) => _enter(),
        onExit: (_) => _exit(),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final trigger = _watched(widget.builder(context, _hover));
    if (widget.panel == null) return trigger;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.topLeft,
          showWhenUnlinked: false,
          // The overlay hands down the whole screen; the panel wants its own
          // size, measured from where the follower put it.
          child: Align(
            alignment: Alignment.topLeft,
            child: _watched(widget.panel!),
          ),
        ),
        child: trigger,
      ),
    );
  }
}
