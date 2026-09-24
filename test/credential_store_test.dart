// Credentials live in the system's secret store rather than in preferences,
// which are a plain file. The part worth testing is every way that store can
// let the app down — not there, turned down at its prompt, taking writes and
// keeping nothing — because in none of them may a credential be lost.
import 'package:codora/core/secret_store.dart';
import 'package:codora/core/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

MemorySecretStore get store => SecretStore.instance as MemorySecretStore;

Future<Map<String, Object>> prefs() async {
  final p = await SharedPreferences.getInstance();
  return {for (final k in p.getKeys()) k: p.get(k)!};
}

void main() {
  resetBootstrapState();

  test('credentials go to the secret store, the rest to preferences',
      () async {
    await const AppSettings(
      v2exToken: 'tok',
      linuxdoCookie: 'cf_clearance=a; _t=b',
      juejinCookie: 'sessionid=c',
      themeMode: 'dark',
    ).save();

    expect(store.values, {
      'v2exToken': 'tok',
      'linuxdoCookie': 'cf_clearance=a; _t=b',
      'juejinCookie': 'sessionid=c',
    });
    final plain = await prefs();
    expect(plain['themeMode'], 'dark');
    expect(plain.keys, isNot(contains('v2exToken')));
    expect(plain.keys, isNot(contains('linuxdoCookie')));
    expect(plain.keys, isNot(contains('juejinCookie')));

    final loaded = await AppSettings.load();
    expect(loaded.v2exToken, 'tok');
    expect(loaded.linuxdoCookie, 'cf_clearance=a; _t=b');
    expect(loaded.juejinCookie, 'sessionid=c');
    expect(loaded.themeMode, 'dark');
  });

  test('credentials from an older version move across on launch', () async {
    SharedPreferences.setMockInitialValues({
      'v2exToken': 'old-token',
      'linuxdoCookie': 'cf_clearance=x',
      'juejinCookie': '',
      'themeMode': 'light',
    });

    final loaded = await AppSettings.load();
    expect(loaded.v2exToken, 'old-token');
    expect(loaded.linuxdoCookie, 'cf_clearance=x');
    expect(loaded.themeMode, 'light');

    expect(store.values,
        {'v2exToken': 'old-token', 'linuxdoCookie': 'cf_clearance=x'});
    final plain = await prefs();
    expect(plain.keys, isNot(contains('v2exToken')));
    expect(plain.keys, isNot(contains('linuxdoCookie')));
    expect(plain.keys, isNot(contains('juejinCookie')));
    expect(plain['themeMode'], 'light');
  });

  test('with no store to move them to, they stay where they were', () async {
    SharedPreferences.setMockInitialValues({'v2exToken': 'old-token'});
    store.unavailable = true;

    final loaded = await AppSettings.load();
    expect(loaded.v2exToken, 'old-token');
    expect((await prefs())['v2exToken'], 'old-token');
  });

  test('a store that keeps nothing is not trusted with them', () async {
    SharedPreferences.setMockInitialValues({'v2exToken': 'old-token'});
    store.forgetful = true;

    expect((await AppSettings.load()).v2exToken, 'old-token');
    expect((await prefs())['v2exToken'], 'old-token',
        reason: 'the only copy must not be dropped');
  });

  test('a save the store will not take lands in preferences instead, '
      'and moves across once the store is back', () async {
    store.unavailable = true;
    await const AppSettings(v2exToken: 'new').save();
    expect((await prefs())['v2exToken'], 'new');

    store.unavailable = false;
    AppSettings.forgetWhatIsKept();
    expect((await AppSettings.load()).v2exToken, 'new');
    expect(store.values['v2exToken'], 'new');
    expect((await prefs()).keys, isNot(contains('v2exToken')));
  });

  test('one left behind in preferences is newer than the store', () async {
    // The store had a token, then a later save could not reach it and wrote
    // to preferences. The store's copy is the stale one.
    store.values['v2exToken'] = 'stale';
    SharedPreferences.setMockInitialValues({'v2exToken': 'fresh'});
    expect((await AppSettings.load()).v2exToken, 'fresh');
    expect(store.values['v2exToken'], 'fresh');
  });

  test('clearing a credential takes it out of the store', () async {
    store.values.addAll({'v2exToken': 'tok', 'juejinCookie': 'sessionid=c'});
    final loaded = await AppSettings.load();
    await loaded.copyWith(v2exToken: '').save();
    expect(store.values, {'juejinCookie': 'sessionid=c'});
    expect((await AppSettings.load()).v2exToken, '');
  });

  test('signing out of linux.do keeps the challenge in the store', () async {
    store.values['linuxdoCookie'] = 'cf_clearance=a; _t=b; _forum_session=c';
    final loaded = await AppSettings.load();
    await loaded.withLinuxdoSignedOut().save();
    expect(store.values['linuxdoCookie'], 'cf_clearance=a');
  });

  test('a store turned down at launch is not emptied by the next save',
      () async {
    // The reader said no to the Keychain's prompt: the app starts without
    // their token, but the token is still there. Changing the theme must not
    // write the empty string over it.
    store.values['v2exToken'] = 'tok';
    store.unavailable = true;
    final loaded = await AppSettings.load();
    expect(loaded.v2exToken, '');

    store.unavailable = false;
    await loaded.copyWith(themeMode: 'dark').save();
    expect(store.values['v2exToken'], 'tok');
  });

  test('but a credential typed in after that is saved', () async {
    store.unavailable = true;
    final loaded = await AppSettings.load();
    store.unavailable = false;
    await loaded.copyWith(v2exToken: 'typed').save();
    expect(store.values['v2exToken'], 'typed');
  });
}
