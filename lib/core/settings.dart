import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const kDesktopUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.4 Safari/605.1.15';

class AppSettings {
  const AppSettings({
    this.v2exToken = '',
    this.v2exProxy = '',
    this.v2exProxyImages = true,
    this.linuxdoCookie = '',
    this.linuxdoUserAgent = kDesktopUserAgent,
    this.juejinCookie = '',
    this.themeMode = 'system',
    this.hiddenSites = const {},
  });
  final String v2exToken;

  /// Reverse proxy V2EX is read through. Empty means a direct connection.
  final String v2exProxy;

  /// Whether pictures inside V2EX posts go through [v2exProxy] as well.
  ///
  /// On by default, because a network that cannot reach the forum cannot
  /// reach its avatars either, and a feed of broken pictures is not a working
  /// feed. It stays a separate switch: a thread links images from whatever
  /// host the author used, and those are not always worth proxying.
  final bool v2exProxyImages;

  final String linuxdoCookie;
  final String linuxdoUserAgent;
  final String juejinCookie;
  final String themeMode;

  /// Sites switched off in settings. Stored as the exceptions rather than the
  /// inclusions so a site added in a later version shows up by default.
  final Set<SiteId> hiddenSites;

  bool get linuxdoReady => linuxdoCookie.contains('cf_clearance=');
  bool get linuxdoLoggedIn => linuxdoCookie.contains('_t=');

  bool shows(SiteId site) => !hiddenSites.contains(site);

  /// Whether [site]'s pictures should follow its proxy. Only V2EX has one to
  /// follow, so every other site answers yes and is left alone.
  bool proxiesImages(SiteId site) => site != SiteId.v2ex || v2exProxyImages;

  AppSettings withSiteShown(SiteId site, bool shown) => copyWith(
        hiddenSites: {
          for (final s in hiddenSites)
            if (s != site) s,
          if (!shown) site,
        },
      );

  AppSettings copyWith({
    String? v2exToken,
    String? v2exProxy,
    bool? v2exProxyImages,
    String? linuxdoCookie,
    String? linuxdoUserAgent,
    String? juejinCookie,
    String? themeMode,
    Set<SiteId>? hiddenSites,
  }) =>
      AppSettings(
        v2exToken: v2exToken ?? this.v2exToken,
        v2exProxy: v2exProxy ?? this.v2exProxy,
        v2exProxyImages: v2exProxyImages ?? this.v2exProxyImages,
        linuxdoCookie: linuxdoCookie ?? this.linuxdoCookie,
        linuxdoUserAgent: linuxdoUserAgent ?? this.linuxdoUserAgent,
        juejinCookie: juejinCookie ?? this.juejinCookie,
        themeMode: themeMode ?? this.themeMode,
        hiddenSites: hiddenSites ?? this.hiddenSites,
      );

  /// Loaded once before the first frame, so nothing ever renders against
  /// empty credentials and then has to correct itself.
  static AppSettings bootstrap = const AppSettings();

  static Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final hidden = p.getStringList('hiddenSites') ?? const [];
    return AppSettings(
      v2exToken: p.getString('v2exToken') ?? '',
      v2exProxy: p.getString('v2exProxy') ?? '',
      v2exProxyImages: p.getBool('v2exProxyImages') ?? true,
      linuxdoCookie: p.getString('linuxdoCookie') ?? '',
      linuxdoUserAgent: p.getString('linuxdoUserAgent') ?? kDesktopUserAgent,
      juejinCookie: p.getString('juejinCookie') ?? '',
      themeMode: p.getString('themeMode') ?? 'system',
      // Read as an intersection, so a name from a newer version — or a
      // hand-edited one — is simply ignored.
      hiddenSites: {
        for (final site in SiteId.values)
          if (hidden.contains(site.name)) site,
      },
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    // The keys are independent, so they go out together rather than as eight
    // platform round trips in a row.
    await Future.wait([
      p.setString('v2exToken', v2exToken),
      p.setString('v2exProxy', v2exProxy),
      p.setBool('v2exProxyImages', v2exProxyImages),
      p.setString('linuxdoCookie', linuxdoCookie),
      p.setString('linuxdoUserAgent', linuxdoUserAgent),
      p.setString('juejinCookie', juejinCookie),
      p.setString('themeMode', themeMode),
      p.setStringList('hiddenSites', [for (final s in hiddenSites) s.name]),
    ]);
  }
}
