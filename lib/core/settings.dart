import 'package:shared_preferences/shared_preferences.dart';

import 'block_list.dart';
import 'disk_cache.dart';
import 'models.dart';
import 'util.dart';

/// The cookie Cloudflare grants for passing its challenge.
///
/// It is bound to the browser that earned it, down to its TLS fingerprint,
/// so it is the one credential that cannot usefully be carried in from
/// somewhere else.
const kLinuxdoClearance = 'cf_clearance';

/// The cookie Discourse sets once a reader is actually signed in. It is the
/// only one that means that, and nothing else should be read as it.
const kLinuxdoSignIn = '_t';

/// What has to go when signing out.
///
/// `_forum_session` is Rails' own session cookie: Discourse hands one to
/// every visitor, signed in or not, so it says nothing about who you are —
/// but it has to be dropped alongside the sign-in, or the server goes on
/// treating the browser as the same session.
const kLinuxdoSessionCookies = {kLinuxdoSignIn, '_forum_session'};

const kDesktopUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.4 Safari/605.1.15';

class AppSettings {
  const AppSettings({
    this.v2exToken = '',
    this.v2exProxy = '',
    this.v2exProxyImages = true,
    this.v2exSeenNotification = 0,
    this.linuxdoCookie = '',
    this.linuxdoUserAgent = kDesktopUserAgent,
    this.juejinCookie = '',
    this.themeMode = 'system',
    this.cacheLimit = kDefaultCacheLimit,
    this.hiddenSites = const {},
    this.blocks = BlockList.empty,
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

  /// Newest V2EX notification the reader has been shown the list at.
  ///
  /// V2EX's API has no read state of its own — it hands back the whole
  /// history either way — so the app keeps its own high-water mark. Zero
  /// means the list has never been opened from here, and the card says 消息
  /// rather than announcing hundreds of old ones as unread.
  final int v2exSeenNotification;

  final String linuxdoCookie;
  final String linuxdoUserAgent;
  final String juejinCookie;
  final String themeMode;

  /// How much disk the cache may use before the oldest pictures are dropped.
  final int cacheLimit;

  /// Sites switched off in settings. Stored as the exceptions rather than the
  /// inclusions so a site added in a later version shows up by default.
  final Set<SiteId> hiddenSites;

  /// Topics kept out of every list.
  final BlockList blocks;

  bool get linuxdoReady => cookieHeaderHas(linuxdoCookie, kLinuxdoClearance);
  bool get linuxdoLoggedIn => cookieHeaderHas(linuxdoCookie, kLinuxdoSignIn);

  bool shows(SiteId site) => !hiddenSites.contains(site);

  /// Whether [site]'s pictures should follow its proxy. Only V2EX has one to
  /// follow, so every other site answers yes and is left alone.
  bool proxiesImages(SiteId site) => site != SiteId.v2ex || v2exProxyImages;

  /// The reader's high-water mark in [site]'s inbox. Only V2EX keeps one;
  /// every other site answers zero, which reads as "never opened".
  int seenNotification(SiteId site) =>
      site == SiteId.v2ex ? v2exSeenNotification : 0;

  AppSettings withNotificationsSeen(SiteId site, int id) =>
      site == SiteId.v2ex ? copyWith(v2exSeenNotification: id) : this;

  /// The same credentials with the sign-in dropped and the clearance kept.
  ///
  /// Signing out should not cost the reader the challenge they already sat
  /// through: anonymous browsing still needs it, and earning it again is the
  /// slow part.
  AppSettings withLinuxdoSignedOut() => copyWith(
        linuxdoCookie: [
          for (final pair in linuxdoCookie.split(';'))
            if (!kLinuxdoSessionCookies.contains(pair.trim().split('=').first))
              pair.trim(),
        ].where((p) => p.isNotEmpty).join('; '),
      );

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
    int? v2exSeenNotification,
    String? linuxdoCookie,
    String? linuxdoUserAgent,
    String? juejinCookie,
    String? themeMode,
    int? cacheLimit,
    Set<SiteId>? hiddenSites,
    BlockList? blocks,
  }) =>
      AppSettings(
        v2exToken: v2exToken ?? this.v2exToken,
        v2exProxy: v2exProxy ?? this.v2exProxy,
        v2exProxyImages: v2exProxyImages ?? this.v2exProxyImages,
        v2exSeenNotification:
            v2exSeenNotification ?? this.v2exSeenNotification,
        linuxdoCookie: linuxdoCookie ?? this.linuxdoCookie,
        linuxdoUserAgent: linuxdoUserAgent ?? this.linuxdoUserAgent,
        juejinCookie: juejinCookie ?? this.juejinCookie,
        themeMode: themeMode ?? this.themeMode,
        cacheLimit: cacheLimit ?? this.cacheLimit,
        hiddenSites: hiddenSites ?? this.hiddenSites,
        blocks: blocks ?? this.blocks,
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
      v2exSeenNotification: p.getInt('v2exSeenNotification') ?? 0,
      linuxdoCookie: p.getString('linuxdoCookie') ?? '',
      linuxdoUserAgent: p.getString('linuxdoUserAgent') ?? kDesktopUserAgent,
      juejinCookie: p.getString('juejinCookie') ?? '',
      themeMode: p.getString('themeMode') ?? 'system',
      cacheLimit: p.getInt('cacheLimit') ?? kDefaultCacheLimit,
      // Read as an intersection, so a name from a newer version — or a
      // hand-edited one — is simply ignored.
      hiddenSites: {
        for (final site in SiteId.values)
          if (hidden.contains(site.name)) site,
      },
      blocks: BlockList(
        keywords: {...?p.getStringList('blockedKeywords')},
        // An entry for a site this build does not know is dropped, the way
        // the switched-off sites are read.
        authors: {
          for (final e in p.getStringList('blockedAuthors') ?? const <String>[])
            if (BlockList.parse(e) != null) e,
        },
        sections: {
          for (final e in p.getStringList('blockedSections') ?? const <String>[])
            if (BlockList.parse(e) != null) e,
        },
      ),
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    // The keys are independent, so they go out together rather than as ten
    // platform round trips in a row.
    await Future.wait([
      p.setString('v2exToken', v2exToken),
      p.setString('v2exProxy', v2exProxy),
      p.setBool('v2exProxyImages', v2exProxyImages),
      p.setInt('v2exSeenNotification', v2exSeenNotification),
      p.setString('linuxdoCookie', linuxdoCookie),
      p.setString('linuxdoUserAgent', linuxdoUserAgent),
      p.setString('juejinCookie', juejinCookie),
      p.setString('themeMode', themeMode),
      p.setInt('cacheLimit', cacheLimit),
      p.setStringList('hiddenSites', [for (final s in hiddenSites) s.name]),
      p.setStringList('blockedKeywords', [...blocks.keywords]),
      p.setStringList('blockedAuthors', [...blocks.authors]),
      p.setStringList('blockedSections', [...blocks.sections]),
    ]);
  }
}
