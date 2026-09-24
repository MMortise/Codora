// linux.do is read through a WebView, and the WebView plugin has no Linux
// implementation. On Linux the site cannot be reached at all, so it should
// say so — in the settings card, in the feed, on the rail — instead of
// offering a browser that is not there, and start switched off.
import 'package:codora/core/models.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/sources/linuxdo_source.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

LinuxDoSource signedIn() => LinuxDoSource(
      cookie: 'cf_clearance=a; _t=b',
      userAgent: kDesktopUserAgent,
    );

void main() {
  resetBootstrapState();

  void runningOn(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  }

  group('on Linux', () {
    test('linux.do says it cannot be read here', () {
      runningOn(TargetPlatform.linux);
      final source = signedIn();
      expect(LinuxDoSource.supported, isFalse);
      expect(source.access.level, AccessLevel.blocked);
      expect(source.access.label, '此平台不支持');
      expect(source.accessNote, LinuxDoSource.unsupportedMessage);
    });

    test('and offers nothing that would need the browser', () {
      runningOn(TargetPlatform.linux);
      final source = signedIn();
      expect(source.member, isNull);
      expect(source.reply, isNull);
      expect(source.like, isNull);
      expect(source.uploadImage, isNull);
    });

    test('a feed fails with the reason, not a challenge to pass', () async {
      runningOn(TargetPlatform.linux);
      final source = signedIn();
      final sections = await source.sections();
      expect(
        source.fetchTopics(sections.first),
        throwsA(predicate((e) =>
            e is! AuthRequiredException &&
            '$e'.contains(LinuxDoSource.unsupportedMessage))),
      );
    });

    test('linux.do starts switched off', () async {
      runningOn(TargetPlatform.linux);
      final loaded = await AppSettings.load();
      expect(loaded.shows(SiteId.linuxdo), isFalse);
      expect(loaded.shows(SiteId.v2ex), isTrue);
    });

    test('but a reader who switched it on keeps it on', () async {
      runningOn(TargetPlatform.linux);
      SharedPreferences.setMockInitialValues({'hiddenSites': <String>[]});
      final loaded = await AppSettings.load();
      expect(loaded.shows(SiteId.linuxdo), isTrue);
    });
  });

  group('elsewhere', () {
    test('linux.do works as it always has', () async {
      runningOn(TargetPlatform.macOS);
      final source = signedIn();
      expect(LinuxDoSource.supported, isTrue);
      expect(source.access.level, AccessLevel.full);
      expect(source.reply, isNotNull);
      expect((await AppSettings.load()).shows(SiteId.linuxdo), isTrue);
    });
  });
}
