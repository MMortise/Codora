import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Where the reader was when they last closed the app: which site, which board
/// on each, and where the window stood.
///
/// Kept apart from [AppSettings] because it changes with every click. The
/// settings object is watched by the whole app, and rebuilding everything
/// because a board was picked would be paying for nothing.
///
/// Each part is written on its own the moment it changes rather than all
/// together on the way out: a desktop app is as often killed or logged out
/// from under as it is quit, and nothing is written on those.
class LastPlace {
  const LastPlace({this.site, this.sections = const {}, this.window});

  static const _siteKey = 'lastSite';
  static const _sectionPrefix = 'lastSection.';
  static const _windowKey = 'windowBounds';

  /// The site last on screen. Settings is never remembered as a place: it is
  /// somewhere to go and fix a thing, not somewhere to come back to.
  final SiteId? site;

  /// The board last picked on each site.
  final Map<SiteId, String> sections;

  /// The window's frame, in the screen coordinates the window manager uses.
  final Rect? window;

  /// Loaded once before the first frame, like the settings.
  static LastPlace bootstrap = const LastPlace();

  static Future<LastPlace> load() async {
    final p = await SharedPreferences.getInstance();
    final bounds = p.getStringList(_windowKey)?.map(double.tryParse).toList();
    return LastPlace(
      site: SiteId.values.asNameMap()[p.getString(_siteKey)],
      sections: {
        for (final site in SiteId.values)
          site: ?p.getString('$_sectionPrefix${site.name}'),
      },
      window: bounds != null &&
              bounds.length == 4 &&
              bounds.every((v) => v != null && v.isFinite)
          ? Rect.fromLTWH(bounds[0]!, bounds[1]!, bounds[2]!, bounds[3]!)
          : null,
    );
  }

  static Future<void> rememberSite(SiteId site) async {
    bootstrap = LastPlace(
        site: site, sections: bootstrap.sections, window: bootstrap.window);
    final p = await SharedPreferences.getInstance();
    await p.setString(_siteKey, site.name);
  }

  static Future<void> rememberSection(SiteId site, String id) async {
    bootstrap = LastPlace(
      site: bootstrap.site,
      sections: {...bootstrap.sections, site: id},
      window: bootstrap.window,
    );
    final p = await SharedPreferences.getInstance();
    await p.setString('$_sectionPrefix${site.name}', id);
  }

  static Future<void> rememberWindow(Rect frame) async {
    bootstrap = LastPlace(
        site: bootstrap.site, sections: bootstrap.sections, window: frame);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_windowKey, [
      for (final v in [frame.left, frame.top, frame.width, frame.height]) '$v',
    ]);
  }
}
