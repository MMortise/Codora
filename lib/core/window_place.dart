import 'dart:async';
import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'last_place.dart';

/// How much of a window's top edge has to be on some display for it to be
/// put back where it was: enough to see it and to drag it by.
const kReachableStrip = Size(120, 24);

/// Where to open a window last seen at [saved], given the displays there are
/// now.
///
/// The size always comes back, grown to [minimum] if it has to be. The
/// position comes back only if the window's top edge would still be on a
/// display: with the one it was on unplugged — a Sidecar iPad, a monitor left
/// at the office — putting it back where it was would open it somewhere
/// nobody can see or reach, and centring it is the better answer.
({Size size, Offset? position}) restorableFrame(
  Rect saved,
  List<Rect> displays, {
  required Size minimum,
}) {
  final size = Size(
    saved.width < minimum.width ? minimum.width : saved.width,
    saved.height < minimum.height ? minimum.height : saved.height,
  );
  final strip = Rect.fromLTWH(
      saved.left, saved.top, size.width, kReachableStrip.height);
  final reachable = displays.any((display) {
    final seen = display.intersect(strip);
    return seen.width >= kReachableStrip.width &&
        seen.height >= kReachableStrip.height;
  });
  return (size: size, position: reachable ? saved.topLeft : null);
}

/// The displays' usable areas, in the coordinates the window manager uses —
/// or none, when they cannot be read, which reads as "centre it".
Future<List<Rect>> visibleDisplays() async {
  try {
    final displays = await screenRetriever.getAllDisplays();
    return [
      for (final d in displays)
        (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size),
    ];
  } catch (_) {
    return const [];
  }
}

/// Writes the window's frame down whenever the reader moves or resizes it.
///
/// A drag reports dozens of positions a second; only where it comes to rest
/// is worth keeping, so each report pushes the write back until they stop.
class WindowPlaceKeeper with WindowListener {
  WindowPlaceKeeper._();

  static final instance = WindowPlaceKeeper._();

  static const settleFor = Duration(milliseconds: 500);

  Timer? _pending;

  void start() => windowManager.addListener(this);

  void _changed() {
    _pending?.cancel();
    _pending = Timer(settleFor, _write);
  }

  Future<void> _write() async {
    try {
      // A full-screen or maximised frame is the display's, not the reader's:
      // coming back from one, the window should be the size they chose.
      if (await windowManager.isFullScreen() ||
          await windowManager.isMaximized() ||
          await windowManager.isMinimized()) {
        return;
      }
      await LastPlace.rememberWindow(await windowManager.getBounds());
    } catch (_) {
      // Losing one remembered position is not worth a crash.
    }
  }

  @override
  void onWindowResize() => _changed();

  @override
  void onWindowMove() => _changed();
}
