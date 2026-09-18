import 'package:flutter/material.dart';

import '../app_theme.dart';

/// A soft panel: the largest radius in the system, one hairline, no shadow.
/// Depth comes from the colour step between canvas and panel.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.radius = Radii.panel,
    this.color,
    this.bordered = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final Color? color;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.panel,
        borderRadius: BorderRadius.circular(radius),
        border: bordered ? Border.all(color: p.line) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Small round-cornered count/status pill. [tone] tints the text; the fill is
/// always the raised surface so counts never compete with a selection.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.icon, this.tone, this.filled = false});
  final String label;
  final IconData? icon;
  final Color? tone;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = tone ?? p.inkMuted;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 8 : 7, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? fg.withValues(alpha: 0.14) : p.raised,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
        ],
        Text(label,
            style: TextStyle(
                fontSize: 11.5, height: 1.1, color: fg, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Icon button sized for the top bar: quiet by default, accent-washed on hover.
class QuietIconButton extends StatefulWidget {
  const QuietIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 17,
    this.box = 32,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  /// The square it reaches over. The top bar has room for the full one; a
  /// card is narrower, and an action in its corner should not take a third of
  /// the way across it.
  final double box;

  @override
  State<QuietIconButton> createState() => _QuietIconButtonState();
}

class _QuietIconButtonState extends State<QuietIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = widget.onPressed != null;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        // A disabled action says so under the pointer as well as in its
        // colour, rather than leaving the arrow and looking clickable.
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: Motion.quick,
            curve: Motion.curve,
            width: widget.box,
            height: widget.box,
            decoration: BoxDecoration(
              color: _hover && enabled ? p.raised : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.block),
            ),
            child: AnimatedSwitcher(
              duration: Motion.quick,
              child: Icon(
                widget.icon,
                key: ValueKey('${widget.icon.codePoint}-$_hover-$enabled'),
                size: widget.size,
                color: enabled ? (_hover ? p.ink : p.inkMuted) : p.inkFaint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
