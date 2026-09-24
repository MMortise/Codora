// Shared scaffolding for tests that touch stored settings.
import 'dart:typed_data';

import 'package:codora/app_theme.dart';
import 'package:codora/core/forum_source.dart';
import 'package:codora/core/last_place.dart';
import 'package:codora/core/models.dart';
import 'package:codora/core/read_log.dart';
import 'package:codora/core/secret_store.dart';
import 'package:codora/core/settings.dart';
import 'package:codora/core/snapshot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clears the process-wide state the app loads before its first frame.
///
/// `AppSettings.bootstrap`, `ReadLog.bootstrap` and `LastPlace.bootstrap` are
/// statics, so a test that left one set would decide where the next file
/// starts. Call once per `main`.
void resetBootstrapState() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecretStore.instance = MemorySecretStore();
    AppSettings.forgetWhatIsKept();
    AppSettings.bootstrap = const AppSettings();
    ReadLog.bootstrap = ReadLog.bootstrap.cleared();
    Snapshots.instance = memorySnapshots();
    LastPlace.bootstrap = const LastPlace();
  });
  tearDown(() => AppSettings.bootstrap = const AppSettings());
}

/// A container reading [settings], disposed when the test ends.
ProviderContainer containerWith([
  AppSettings settings = const AppSettings(),
  List<Override> overrides = const [],
]) {
  AppSettings.bootstrap = settings;
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  return container;
}

/// Pumps [child] as the app would, and hands back the container behind it so a
/// test can read what the widgets read.
Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  Widget child, {
  AppSettings settings = const AppSettings(),
  Size? size,
  List<Override> overrides = const [],
}) async {
  final container = containerWith(settings, overrides);
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: child),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

/// Tears the tree down and drops [container] from inside the test body.
///
/// A provider that holds a timer — the profile card re-reads itself on one —
/// is still holding it when the framework checks for stragglers, and that
/// check runs before `addTearDown` does. Cleaning up here rather than there
/// keeps the check meaningful instead of muting it.
Future<void> disposeApp(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
}

/// A site that answers however a test tells it to, and counts the asking.
///
/// The profile card is built on [ForumSource.member], so the way to test it
/// without a network is to stand in for the site itself — which also keeps
/// the real provider, timers and all, in the picture.
class FakeSource implements ForumSource {
  FakeSource(this.answer,
      {this.id = SiteId.v2ex, this.onReply, this.onLike, this.onUpload});

  /// Null for a site that cannot say who the reader is.
  final Future<Member> Function()? answer;

  /// Null for a site that cannot be written to, which is what decides
  /// whether the reading pane offers a box at all.
  final SendReply? onReply;

  /// Null for a site with no likes to give.
  final ActOnLike? onLike;

  /// Null for a site that takes no pictures, which is what decides whether
  /// the box offers a picture button.
  final UploadImage? onUpload;

  int calls = 0;

  @override
  Future<Member> Function()? get member => answer == null
      ? null
      : () {
          calls++;
          return answer!();
        };

  @override
  SendReply? get reply => onReply;

  @override
  ActOnLike? get like => onLike;

  @override
  UploadImage? get uploadImage => onUpload;

  @override
  final SiteId id;
  @override
  String get name => id.label;
  @override
  String get glyph => 'V2';
  @override
  String get iconAsset => 'assets/icons/v2ex.png';
  @override
  Uri get homeUrl => Uri.parse('https://www.v2ex.com');
  @override
  String get accessNote => '';
  @override
  SiteAccess get access => const SiteAccess(AccessLevel.full, '');
  @override
  SiteImages get images => SiteImages.plain;
  @override
  Future<List<Section>> sections() async => const [];
  @override
  Future<PageResult<TopicSummary>> fetchTopics(Section s, {String? cursor}) =>
      throw UnimplementedError();
  @override
  Future<TopicDetail> fetchTopic(String id) => throw UnimplementedError();
  @override
  Future<PageResult<Reply>> fetchReplies(String id, {String? cursor}) =>
      throw UnimplementedError();
  @override
  String? topicIdFromUrl(Uri uri) => null;
}

/// Saved lists and threads, kept in memory: a widget test cannot wait on real
/// files. [store] is there to look into, or to fill before a test starts.
Snapshots memorySnapshots([Map<Uri, Uint8List>? store]) {
  final files = store ?? <Uri, Uint8List>{};
  return Snapshots(
    read: (key) async => files[key],
    write: (key, bytes) async => files[key] = bytes,
  );
}

/// A secret store held in memory, which can be told to be out of reach — the
/// way the Keychain is when the reader turns its prompt down, or Linux has no
/// Secret Service running.
class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  /// Every call throws while this is set.
  bool unavailable = false;

  /// Takes writes and keeps nothing, as a misconfigured Keychain group does.
  bool forgetful = false;

  void _check() {
    if (unavailable) throw StateError('secret store unavailable');
  }

  @override
  Future<String?> read(String key) async {
    _check();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _check();
    if (!forgetful) values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _check();
    values.remove(key);
  }
}
