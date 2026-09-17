import 'package:shared_preferences/shared_preferences.dart';

const kDesktopUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/17.4 Safari/605.1.15';

class AppSettings {
  const AppSettings({
    this.v2exToken = '',
    this.linuxdoCookie = '',
    this.linuxdoUserAgent = kDesktopUserAgent,
    this.juejinCookie = '',
    this.themeMode = 'system',
  });
  final String v2exToken;
  final String linuxdoCookie;
  final String linuxdoUserAgent;
  final String juejinCookie;
  final String themeMode;

  bool get linuxdoReady => linuxdoCookie.contains('cf_clearance=');
  bool get linuxdoLoggedIn => linuxdoCookie.contains('_t=');

  AppSettings copyWith({
    String? v2exToken,
    String? linuxdoCookie,
    String? linuxdoUserAgent,
    String? juejinCookie,
    String? themeMode,
  }) =>
      AppSettings(
        v2exToken: v2exToken ?? this.v2exToken,
        linuxdoCookie: linuxdoCookie ?? this.linuxdoCookie,
        linuxdoUserAgent: linuxdoUserAgent ?? this.linuxdoUserAgent,
        juejinCookie: juejinCookie ?? this.juejinCookie,
        themeMode: themeMode ?? this.themeMode,
      );

  /// Loaded once before the first frame, so nothing ever renders against
  /// empty credentials and then has to correct itself.
  static AppSettings bootstrap = const AppSettings();

  static Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return AppSettings(
      v2exToken: p.getString('v2exToken') ?? '',
      linuxdoCookie: p.getString('linuxdoCookie') ?? '',
      linuxdoUserAgent: p.getString('linuxdoUserAgent') ?? kDesktopUserAgent,
      juejinCookie: p.getString('juejinCookie') ?? '',
      themeMode: p.getString('themeMode') ?? 'system',
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('v2exToken', v2exToken);
    await p.setString('linuxdoCookie', linuxdoCookie);
    await p.setString('linuxdoUserAgent', linuxdoUserAgent);
    await p.setString('juejinCookie', juejinCookie);
    await p.setString('themeMode', themeMode);
  }
}
