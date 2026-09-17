import 'package:codora/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the window opens at the agreed size', () {
    expect(kInitialWindowSize, const Size(1200, 640));
  });

  test('the opening width keeps the reading pane', () {
    // The shell puts the list and the post side by side from 940 up; opening
    // narrower than that would hide the pane on first launch.
    expect(kInitialWindowSize.width, greaterThanOrEqualTo(940));
  });
}
