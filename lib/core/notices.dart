import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'models.dart';

/// How many of [member]'s notifications the reader has not seen, as the card
/// counts them.
///
/// A site that counts its own is believed. One that does not is counted from
/// the mark the app keeps, and only once there is one: before the list has
/// ever been opened from here, every notice it has ever sent would count.
int unreadOf(Member member, int seen) =>
    member.unread ?? (seen > 0 ? member.unreadSince(seen) : 0);

/// What to say about the notices that arrived since [announcedUpTo], or null
/// when nothing did.
({String title, String body})? announcementFor(
    SiteId site, Member member, int announcedUpTo) {
  final fresh = [
    for (final n in member.notifications)
      if (n.id > announcedUpTo) n,
  ]..sort((a, b) => b.id.compareTo(a.id));
  if (fresh.isEmpty) return null;
  return (
    title: fresh.length == 1
        ? '${site.label} 有新消息'
        : '${site.label} 有 ${fresh.length} 条新消息',
    body: fresh.first.text,
  );
}

/// The newest notice already announced for each site, kept across launches so
/// a notice is announced once — not again on the next start.
///
/// No mark means the site has never been read from here: its first read sets
/// one without announcing anything, or a first launch would announce the
/// reader's whole history.
class AnnouncedMarks {
  const AnnouncedMarks._(this._marks);

  static const empty = AnnouncedMarks._({});

  static AnnouncedMarks bootstrap = empty;

  final Map<SiteId, int> _marks;

  static String _key(SiteId site) => 'announced.${site.name}';

  int? of(SiteId site) => _marks[site];

  static Future<AnnouncedMarks> load() async {
    final p = await SharedPreferences.getInstance();
    return AnnouncedMarks._({
      for (final site in SiteId.values) site: ?p.getInt(_key(site)),
    });
  }

  /// The marks with [site]'s moved to [mark]. In memory at once — see
  /// [save] for the disk.
  AnnouncedMarks withMark(SiteId site, int mark) =>
      AnnouncedMarks._({..._marks, site: mark});

  Future<void> save(SiteId site) async {
    final mark = _marks[site];
    if (mark == null) return;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_key(site), mark);
  }
}

/// Where announcements go: the system's notifications, and the number on the
/// app's icon.
abstract class NoticeOutlet {
  /// Says [body] under [title], for [site]. Pressing it calls [onOpen].
  Future<void> announce(SiteId site, String title, String body);

  /// Puts [count] on the app's icon, or clears it at zero.
  Future<void> badge(int count);

  /// Called with the site an announcement was for, when it is pressed.
  ValueChanged<SiteId>? onOpen;

  /// The one the app uses. Replaced in tests.
  static NoticeOutlet instance = SystemNoticeOutlet();
}

class SystemNoticeOutlet implements NoticeOutlet {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;
  int _next = 0;

  @override
  ValueChanged<SiteId>? onOpen;

  /// Set up on the first announcement rather than at launch, so the system
  /// asks for permission when there is something to show — not before the
  /// reader has seen the app at all.
  Future<bool> _prepare() => _ready ??= () async {
        try {
          await _plugin.initialize(
            settings: const InitializationSettings(
              macOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
              linux: LinuxInitializationSettings(defaultActionName: '打开'),
              windows: WindowsInitializationSettings(
                appName: 'Codora',
                appUserModelId: 'MMortise.Codora',
                guid: '7b0f6f64-2d1c-4f8e-9c55-1c3d4e5f6a7b',
              ),
            ),
            onDidReceiveNotificationResponse: (response) async {
              final site =
                  SiteId.values.asNameMap()[response.payload ?? ''];
              await windowManager.show();
              await windowManager.focus();
              if (site != null) onOpen?.call(site);
            },
          );
          if (Platform.isMacOS) {
            return await _plugin
                    .resolvePlatformSpecificImplementation<
                        MacOSFlutterLocalNotificationsPlugin>()
                    ?.requestPermissions(alert: true, badge: true) ??
                false;
          }
          return true;
        } catch (_) {
          return false;
        }
      }();

  @override
  Future<void> announce(SiteId site, String title, String body) async {
    if (!await _prepare()) return;
    try {
      await _plugin.show(
        id: _next++,
        title: title,
        body: body,
        payload: site.name,
      );
    } catch (_) {}
  }

  @override
  Future<void> badge(int count) async {
    // Only the Dock has a number to show; the taskbar and Linux docks have
    // no such thing the app can reach.
    if (!Platform.isMacOS) return;
    try {
      await windowManager.setBadgeLabel(count > 0 ? '$count' : null);
    } catch (_) {}
  }
}
