import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'settings.dart';
import 'util.dart';
import 'webview_fetcher.dart';

/// The one origin any of this applies to.
final linuxdoOrigin = Uri.parse('https://linux.do');

/// How long a hand-copied cookie is kept.
///
/// A `Cookie:` header carries names and values and nothing else, so there is
/// no real expiry to honour. Without one the browser would treat it as a
/// session cookie and drop it on the next launch — the app would go back to
/// being anonymous while settings still said otherwise, which is the whole
/// problem this exists to fix. A year is what Discourse itself uses; the
/// server rejects a stale one long before then, and that reads as a normal
/// sign-in prompt rather than a credential quietly vanishing.
const _keepFor = Duration(days: 365);

/// Which of a stored header's cookies are worth writing into the browser.
///
/// The Cloudflare clearance is left out on purpose. It is tied to the browser
/// that earned it, so one carried in from elsewhere is not merely useless but
/// worse than whatever this browser already holds.
List<(String, String)> cookiesToApply(String header) {
  final out = <(String, String)>[];
  for (final raw in header.split(';')) {
    final pair = raw.trim();
    // Values are base64 often enough that only the first `=` separates them.
    final split = pair.indexOf('=');
    if (split <= 0) continue;
    final name = pair.substring(0, split);
    if (name == kLinuxdoClearance) continue;
    out.add((name, pair.substring(split + 1)));
  }
  return out;
}

/// Puts [header] into the browser the feed actually runs in.
///
/// Everything this site serves is fetched inside a WebView, which sends its
/// own cookie jar rather than anything held in settings. A credential that
/// only ever reached settings therefore changed what the app believed without
/// changing what it sent: the card would read 已登录 while every request went
/// out anonymous. This is the step that was missing.
///
/// It matters most for a sign-in the embedded browser cannot perform itself —
/// a passkey, or any provider that refuses to run inside a WebView. Those can
/// be done in a real browser and the result carried across by hand.
Future<void> applyLinuxDoCookies(String header) async {
  final cookies = cookiesToApply(header);
  if (cookies.isEmpty) return;
  final jar = CookieManager.instance();
  final url = WebUri(linuxdoOrigin.toString());
  final expires =
      DateTime.now().add(_keepFor).millisecondsSinceEpoch;
  for (final (name, value) in cookies) {
    await jar.setCookie(
      url: url,
      name: name,
      value: value,
      path: '/',
      expiresDate: expires,
      isSecure: true,
    );
  }
}

/// Which of the two copies of the credentials to believe.
///
/// The browser's, whenever it holds a sign-in of its own. Discourse rotates
/// that cookie as the site is used, so the copy kept in settings goes stale
/// by itself — and writing the stale one back over the browser's, which is
/// what seeding blindly at every launch did, eventually signs the reader out
/// while settings go on holding a `_t` and the app goes on believing all is
/// well. What was stored is for a browser that has nothing: a fresh install,
/// or a sign-in carried in from somewhere else by hand.
@visibleForTesting
String believedLinuxDoCookie({required String held, required String stored}) =>
    cookieHeaderHas(held, kLinuxdoSignIn) ? held : stored;

/// Brings the browser and the stored copy into agreement at launch, and
/// answers with the one to keep.
///
/// Everything this site serves is fetched inside that browser, so whatever it
/// holds is what actually goes out; storing anything else only makes the app
/// wrong about itself.
Future<String> adoptLinuxDoCookies(String stored) async {
  final jar = CookieManager.instance();
  final held = await jar.getCookies(url: WebUri(linuxdoOrigin.toString()));
  final header = believedLinuxDoCookie(
    held: [for (final c in held) '${c.name}=${c.value}'].join('; '),
    stored: stored,
  );
  // Only when the browser has no sign-in of its own is there anything to put
  // there; otherwise this would be the overwrite the whole thing avoids.
  if (header == stored) await applyLinuxDoCookies(stored);
  return header;
}

/// Drops what the embedded browser is holding for linux.do.
///
/// The visible page and the hidden one the feed runs in share a cookie jar,
/// so credentials have to go from there rather than only from stored
/// settings — otherwise the app stops believing it is signed in while every
/// request it sends still is.
///
/// [keepClearance] is the whole difference between signing out and forgetting
/// the site: sitting through Cloudflare again is the slow half, and someone
/// who only wanted out of their account should not have to pay it.
Future<void> clearLinuxDoCookies({bool keepClearance = false}) async {
  final jar = CookieManager.instance();
  final url = WebUri(linuxdoOrigin.toString());
  for (final cookie in await jar.getCookies(url: url)) {
    if (keepClearance && cookie.name == kLinuxdoClearance) continue;
    await jar.deleteCookie(url: url, name: cookie.name);
  }
  await WebViewFetcher.instance.reset(linuxdoOrigin);
}

/// Ends the session and keeps the clearance.
Future<void> signOutOfLinuxDo() => clearLinuxDoCookies(keepClearance: true);
