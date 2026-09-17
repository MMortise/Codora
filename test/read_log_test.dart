// Read state is what tells a long list apart on a second visit, so it has to
// survive restarts, stay bounded, and never lose track of which site a post
// belongs to.
import 'package:codora/core/models.dart';
import 'package:codora/core/read_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a fresh log knows nothing', () async {
    final log = await ReadLog.load();
    expect(log.length, 0);
    expect(log.contains(SiteId.v2ex, '1'), isFalse);
  });

  test('marking a post read is remembered', () async {
    var log = await ReadLog.load();
    log = log.markRead(SiteId.v2ex, '42');
    expect(log.contains(SiteId.v2ex, '42'), isTrue);
    expect(log.length, 1);
  });

  test('the same id on another site is a different post', () async {
    var log = await ReadLog.load();
    log = log.markRead(SiteId.v2ex, '42');
    expect(log.contains(SiteId.juejin, '42'), isFalse);
    expect(log.contains(SiteId.linuxdo, '42'), isFalse);
  });

  test('re-reading the newest post changes nothing', () async {
    var log = (await ReadLog.load()).markRead(SiteId.v2ex, '1');
    final again = log.markRead(SiteId.v2ex, '1');
    expect(identical(log, again), isTrue,
        reason: 'no write should happen for a no-op');
  });

  test('re-reading an older post moves it to the front', () async {
    var log = await ReadLog.load();
    log = log.markRead(SiteId.v2ex, 'a').markRead(SiteId.v2ex, 'b');
    log = log.markRead(SiteId.v2ex, 'a');
    expect(log.length, 2, reason: 'it must not be stored twice');
    expect(log.contains(SiteId.v2ex, 'a'), isTrue);
    expect(log.contains(SiteId.v2ex, 'b'), isTrue);
  });

  test('it stops growing at the cap, dropping the oldest', () async {
    var log = await ReadLog.load();
    for (var i = 0; i < ReadLog.limit + 50; i++) {
      log = log.markRead(SiteId.v2ex, '$i');
    }
    expect(log.length, ReadLog.limit);
    expect(log.contains(SiteId.v2ex, '0'), isFalse, reason: 'oldest dropped');
    expect(log.contains(SiteId.v2ex, '${ReadLog.limit + 49}'), isTrue,
        reason: 'newest kept');
  });

  test('it survives a restart', () async {
    var log = await ReadLog.load();
    log = log.markRead(SiteId.linuxdo, '2910060');
    await log.save();

    final reloaded = await ReadLog.load();
    expect(reloaded.contains(SiteId.linuxdo, '2910060'), isTrue);
    expect(reloaded.length, 1);
  });

  test('clearing empties it', () async {
    var log = (await ReadLog.load()).markRead(SiteId.v2ex, '1');
    log = log.cleared();
    expect(log.length, 0);
    expect(log.contains(SiteId.v2ex, '1'), isFalse);
  });
}
