import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../core/util.dart';

/// A timestamp shown the way people read it ("11 分钟前"), with the exact
/// moment one hover away. Used everywhere a time appears, so the two forms
/// never drift apart.
class RelativeTime extends StatelessWidget {
  const RelativeTime(this.time, {super.key, this.style});

  final DateTime? time;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Text(
      relativeTime(time),
      style: style ?? TextStyle(fontSize: 11.5, color: p.inkFaint),
    );
    if (time == null) return text;
    return Tooltip(message: fullTime(time), child: text);
  }
}
