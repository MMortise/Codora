import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../app_theme.dart';

/// Scrolls [controller] until item [index] of [count] is on screen.
///
/// The items are laid out lazily and are as tall as their contents, so no
/// offset can be worked out ahead: an item that has been built is scrolled
/// to directly, and one that has not is jumped toward — from where the built
/// items sit and how tall they run — until it is, a frame at a time.
///
/// [alignment] is where the item should end up, 0 at the top of the viewport
/// and 1 at the bottom. Null means "just far enough to show all of it", and
/// leaves an item already in view where it is.
void revealItem({
  required ScrollController controller,
  required int count,
  required int index,
  required RenderBox? Function(int index) built,
  double? alignment,
  double inset = 0,
  int attempts = 20,
}) {
  if (!controller.hasClients || index < 0 || index >= count) return;
  final position = controller.position;
  final item = built(index);
  if (item != null) {
    final viewport = RenderAbstractViewport.of(item);
    final double target;
    if (alignment != null) {
      target = viewport.getOffsetToReveal(item, alignment).offset - inset;
    } else {
      final top = viewport.getOffsetToReveal(item, 0).offset;
      final bottom = viewport.getOffsetToReveal(item, 1).offset;
      if (position.pixels > top) {
        target = top;
      } else if (position.pixels < bottom) {
        target = bottom;
      } else {
        return;
      }
    }
    controller.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: Motion.swap,
      curve: Motion.curve,
    );
    return;
  }
  if (attempts <= 0) return;
  // The first and last items laid out right now, and where they sit.
  int? first, last;
  RenderBox? firstBox, lastBox;
  for (var i = 0; i < count; i++) {
    final box = built(i);
    if (box == null) continue;
    if (first == null) {
      first = i;
      firstBox = box;
    }
    last = i;
    lastBox = box;
  }
  final double guess;
  if (first == null || last == null) {
    // Nothing built yet — the items start further down than the screen
    // reaches. Going a screen at a time finds them.
    guess = position.pixels + position.viewportDimension * 1.5;
  } else {
    final viewport = RenderAbstractViewport.of(firstBox!);
    final firstTop = viewport.getOffsetToReveal(firstBox, 0).offset;
    final lastBottom =
        viewport.getOffsetToReveal(lastBox!, 0).offset + lastBox.size.height;
    final perItem = (lastBottom - firstTop) / (last - first + 1);
    guess = index > last
        ? lastBottom + (index - last - 1) * perItem
        : firstTop - (first - index) * perItem;
  }
  controller.jumpTo((guess - position.viewportDimension / 2)
      .clamp(position.minScrollExtent, position.maxScrollExtent));
  WidgetsBinding.instance.addPostFrameCallback((_) => revealItem(
        controller: controller,
        count: count,
        index: index,
        built: built,
        alignment: alignment,
        inset: inset,
        attempts: attempts - 1,
      ));
}

/// The box [key] is attached to, if it has been laid out.
RenderBox? laidOut(GlobalKey? key) {
  final box = key?.currentContext?.findRenderObject();
  return box is RenderBox && box.attached && box.hasSize ? box : null;
}
