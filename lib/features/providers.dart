import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/disk_cache.dart';
import '../core/forum_source.dart';
import '../core/last_place.dart';
import '../core/library.dart';
import '../core/linuxdo_session.dart';
import '../core/models.dart';
import '../core/read_log.dart';
import '../core/settings.dart';
import '../core/snapshot.dart';
import '../core/util.dart';
import '../core/updates.dart';
import '../core/webview_fetcher.dart';
import '../sources/juejin_source.dart';
import '../sources/linuxdo_source.dart';
import '../sources/v2ex_source.dart';

enum NavTarget { v2ex, linuxdo, juejin, library, settings }

extension NavTargetX on NavTarget {
  SiteId? get site => switch (this) {
        NavTarget.v2ex => SiteId.v2ex,
        NavTarget.linuxdo => SiteId.linuxdo,
        NavTarget.juejin => SiteId.juejin,
        NavTarget.library || NavTarget.settings => null,
      };
}

extension SiteIdNav on SiteId {
  /// Reads [NavTargetX.site] backwards rather than restating it, so the two
  /// directions cannot disagree about a site added later.
  NavTarget get target => NavTarget.values.firstWhere((t) => t.site == this);
}

/// The two halves of the settings page: the forums, and everything that is
/// about the app rather than a site.
enum SettingsTab {
  forums('论坛'),
  general('常规');

  const SettingsTab(this.label);
  final String label;
}

/// Which half is open. Shared rather than local to the page so that sending
/// someone to settings can put them on the tab holding the fix.
final settingsTabProvider =
    StateProvider<SettingsTab>((_) => SettingsTab.forums);

/// Where the reader has clicked. Read through [currentNavProvider], which is
/// the one that accounts for sites switched off.
///
/// Opens on the site the reader was last on; [rememberPlaceProvider] keeps
/// that up to date. A site since switched off is handled the same way as one
/// switched off mid-session, by [currentNavProvider].
final navProvider = StateProvider<NavTarget>(
    (_) => LastPlace.bootstrap.site?.target ?? NavTarget.v2ex);

/// The tab actually on screen.
///
/// A site the reader has switched off cannot be the current one, so the shell
/// falls back to the first site still showing — and to settings when none is,
/// which is also the only way back from there.
final currentNavProvider = Provider<NavTarget>((ref) {
  final nav = ref.watch(navProvider);
  final visible = ref.watch(visibleSiteIdsProvider);
  if (nav.site == null || visible.contains(nav.site)) return nav;
  return visible.isEmpty ? NavTarget.settings : visible.first.target;
});

// ---------- the app itself ----------

/// The version running, as the build was stamped with it.
final appVersionProvider = FutureProvider<String>(
    (_) async => (await PackageInfo.fromPlatform()).version);

/// A newer release, if one has been published. Asked each time the panel
/// showing it comes on screen, and again whenever the reader asks.
final updateProvider = FutureProvider.autoDispose<Release?>((ref) async {
  final current = await ref.watch(appVersionProvider.future);
  return newerRelease(current);
});

// ---------- settings ----------

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.bootstrap;

  Future<void> patch(AppSettings Function(AppSettings) f) async {
    final prev = state;
    final next = f(prev);
    state = next;
    AppSettings.bootstrap = next;
    await next.save();
    // The cache is a live object, not a stored number: a budget lowered here
    // has to take effect now, not the next time enough pictures happen to
    // trigger a trim.
    if (next.cacheLimit != prev.cacheLimit) {
      DiskCache.instance.limit = next.cacheLimit;
      unawaited(DiskCache.instance.trimTo(next.cacheLimit));
    }
    // linux.do is read inside a WebView, which sends its own cookie jar and
    // knows nothing about what is stored here. Credentials have to be put
    // there or they change what the app believes without changing what it
    // sends. The hidden WebView is then dropped, since it holds the old ones.
    if (next.linuxdoCookie != prev.linuxdoCookie ||
        next.linuxdoUserAgent != prev.linuxdoUserAgent) {
      await applyLinuxDoCookies(next.linuxdoCookie);
      await WebViewFetcher.instance.reset(linuxdoOrigin);
      // The new settings went out above, and with them the profile card set
      // off to read who is signed in now — through the WebView just dropped
      // under it, into the browser before it held the new credentials. Right
      // after signing in, that read came back saying the sign-in had failed
      // and the card kept saying so until its retry a minute later. It is
      // asked again now that the browser is ready for it.
      ref.invalidate(memberProvider(SiteId.linuxdo));
    }
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ---------- read state ----------

class ReadLogNotifier extends Notifier<ReadLog> {
  @override
  ReadLog build() => ReadLog.bootstrap;

  Future<void> markRead(SiteId site, String id) async {
    final next = state.markRead(site, id);
    if (identical(next, state)) return;
    state = next;
    ReadLog.bootstrap = next;
    await next.save();
  }

  /// Keeps what has been seen of a post the reader has open: how many
  /// replies it has, and which of them was last on screen.
  Future<void> recordProgress(SiteId site, String id,
      {int? replies, int? position}) async {
    final next =
        state.withProgress(site, id, replies: replies, position: position);
    if (identical(next, state)) return;
    state = next;
    ReadLog.bootstrap = next;
    await next.save();
  }

  Future<void> clear() async {
    state = state.cleared();
    ReadLog.bootstrap = state;
    await state.save();
  }
}

final readLogProvider =
    NotifierProvider<ReadLogNotifier, ReadLog>(ReadLogNotifier.new);

// ---------- bookmarks and history ----------

class LibraryNotifier extends Notifier<Library> {
  @override
  Library build() => Library.bootstrap;

  Future<void> _set(Library next) async {
    if (identical(next, state)) return;
    state = next;
    Library.bootstrap = next;
    await next.save();
  }

  Future<void> toggleBookmark(SavedTopic topic) =>
      _set(state.toggleBookmark(topic));

  Future<void> visit(SavedTopic topic) => _set(state.withVisit(topic));

  Future<void> clearHistory() => _set(state.withoutHistory());
}

final libraryProvider =
    NotifierProvider<LibraryNotifier, Library>(LibraryNotifier.new);

// ---------- search ----------

/// What is being searched for on each site, while a search is showing in
/// place of a board.
final searchQueryProvider =
    StateProvider.family<String?, SiteId>((_, _) => null);

/// A search runs through the same list a board does, under a section id of
/// its own, so it pages, marks what was read and moves under J and K the way
/// a board does.
const _searchPrefix = 'search:';

String searchSectionId(String query) => '$_searchPrefix$query';

/// The query a section id stands for, or null for a real board.
String? searchQueryOf(String sectionId) => sectionId.startsWith(_searchPrefix)
    ? sectionId.substring(_searchPrefix.length)
    : null;

// ---------- sources ----------

/// Each site watches only the settings it is built from. Watching the whole
/// object would rebuild every source — and so reload every feed — when an
/// unrelated preference like the theme changes.
final sourceProvider = Provider.family<ForumSource, SiteId>((ref, site) {
  T pick<T>(T Function(AppSettings) f) => ref.watch(settingsProvider.select(f));
  return switch (site) {
    SiteId.v2ex => V2exSource(
        token: pick((s) => s.v2exToken),
        proxy: pick((s) => s.v2exProxy),
      ),
    SiteId.linuxdo => LinuxDoSource(
        cookie: pick((s) => s.linuxdoCookie),
        userAgent: pick((s) => s.linuxdoUserAgent),
      ),
    SiteId.juejin => JuejinSource(cookie: pick((s) => s.juejinCookie)),
  };
});

/// How a site's pictures are reached. Held by the provider so the descriptor
/// stays the same object between rebuilds — [SiteImage] restarts a load when
/// it changes.
///
/// The reader's choice about proxying pictures is applied here rather than
/// inside the source: it says nothing about the feed, so baking it into the
/// source would refetch one every time the switch is flipped.
final siteImagesProvider = Provider.family<SiteImages, SiteId>((ref, site) {
  final images = ref.watch(sourceProvider(site)).images;
  final proxied =
      ref.watch(settingsProvider.select((s) => s.proxiesImages(site)));
  // V2EX is the only site that can be proxied, and its descriptor exists for
  // no other reason — a rewritten address with one kind of proxy, a loader
  // with the other — so opting out means an ordinary request.
  return proxied ? images : SiteImages.plain;
});

/// How long a profile is good for.
///
/// It is a slow-moving page — a tagline, a signup number, an inbox that gains
/// a line now and then. Refreshing on a clock rather than when someone looks
/// is the point: the card should already be right when it opens, instead of
/// being one request behind whoever opened it.
const memberFreshFor = Duration(hours: 1);

/// How soon to try again after a failure.
///
/// A profile that could not be read is not a cache. The usual cause is a
/// proxy having a bad minute, and sitting out the full hour would leave the
/// card wrong for far longer than the problem lasted.
const memberRetryAfter = Duration(minutes: 1);

/// Who the stored credentials sign the reader in as.
///
/// Loaded when the app opens rather than when a pointer arrives — see
/// [loadedMembersProvider] — and kept current by re-reading itself on a
/// timer, so nothing about the card waits on a hover.
class MemberNotifier extends AutoDisposeFamilyAsyncNotifier<Member, SiteId> {
  Timer? _next;

  /// Which read counts as the current one.
  ///
  /// A fetch can outlive the build that started it — the site is switched off
  /// while it is in flight, or a credential changes under it. Arming the
  /// timer from a fetch nobody is waiting for any more would leave a timer
  /// nothing cancels, pointed at a provider that is gone.
  Object? _reading;

  @override
  Future<Member> build(SiteId arg) async {
    final fetch = ref.watch(sourceProvider(arg)).member;
    final reading = Object();
    _reading = reading;
    ref.onDispose(() {
      _next?.cancel();
      if (identical(_reading, reading)) _reading = null;
    });
    // Only reachable if the credentials went away mid-flight; the rail reads
    // the same field to decide whether to load a profile at all.
    if (fetch == null) throw StateError('${arg.label} 现在没有可读的个人信息');
    try {
      final member = await fetch();
      _again(memberFreshFor, reading);
      return member;
    } catch (_) {
      _again(memberRetryAfter, reading);
      rethrow;
    }
  }

  void _again(Duration after, Object reading) {
    if (!identical(_reading, reading)) return;
    _next?.cancel();
    _next = Timer(after, ref.invalidateSelf);
  }
}

final memberProvider =
    AsyncNotifierProvider.autoDispose.family<MemberNotifier, Member, SiteId>(
        MemberNotifier.new);

/// The sites whose profile is loaded up front and kept current.
///
/// Watching a provider is what starts it, so this is where the loading
/// actually happens. The rail watches this and the rail is always on screen,
/// which means the profiles are read as the app comes up and stay warm for as
/// long as their site is on the rail — a site switched off stops being asked
/// about, along with everything else it was doing in the background.
final loadedMembersProvider = Provider<List<SiteId>>((ref) {
  final sites = [
    for (final source in ref.watch(visibleSourcesProvider))
      if (source.member != null) source.id,
  ];
  for (final site in sites) {
    ref.watch(memberProvider(site));
  }
  return sites;
});

/// Every site in display order, including the ones switched off — the
/// settings page lists all of them.
final allSourcesProvider = Provider<List<ForumSource>>(
    (ref) => [for (final s in SiteId.values) ref.watch(sourceProvider(s))]);

/// Which sites the rail shows, from the switches alone. Kept separate from
/// [visibleSourcesProvider] so that editing a credential — which rebuilds a
/// source — does not churn the shell's layout or the current tab.
final visibleSiteIdsProvider = Provider<List<SiteId>>((ref) {
  final hidden = ref.watch(settingsProvider.select((s) => s.hiddenSites));
  return [
    for (final site in SiteId.values)
      if (!hidden.contains(site)) site,
  ];
});

/// The sites the rail shows, with the state the rail draws them from.
final visibleSourcesProvider = Provider<List<ForumSource>>((ref) => [
      for (final site in ref.watch(visibleSiteIdsProvider))
        ref.watch(sourceProvider(site)),
    ]);

final sectionsProvider =
    FutureProvider.family<List<Section>, SiteId>((ref, site) {
  return ref.watch(sourceProvider(site)).sections();
});

/// The board picked on each site, starting from the one picked last time.
///
/// What is remembered may not be a board any more — the site dropped it, or a
/// credential changed which boards there are — so the page checks it against
/// the boards the site actually lists before using it.
final selectedSectionProvider = StateProvider.family<String?, SiteId>(
    (_, site) => LastPlace.bootstrap.sections[site]);

/// Writes down each site and board the reader goes to, so the next launch
/// opens on them. The shell watches this for as long as the app is open.
final rememberPlaceProvider = Provider<void>((ref) {
  ref.listen(navProvider, (_, next) {
    if (next.site case final site?) unawaited(LastPlace.rememberSite(site));
  });
  for (final site in SiteId.values) {
    ref.listen(selectedSectionProvider(site), (_, next) {
      if (next != null) unawaited(LastPlace.rememberSection(site, next));
    });
  }
});

/// Stack of opened topics in the detail pane; last is the visible one.
final detailStackProvider =
    StateProvider.family<List<TopicRef>, SiteId>((_, _) => const []);

/// Who is reading [site], as far as saved copies are concerned — see
/// [Snapshots]. A fingerprint of the credential, never the credential.
///
/// linux.do counts only as signed in or not: Discourse rotates its sign-in
/// cookie every few minutes, and filing copies under it would throw them all
/// away as often.
final readerProvider = Provider.family<String, SiteId>((ref, site) {
  final credential = ref.watch(settingsProvider.select((s) => switch (site) {
        SiteId.v2ex => s.v2exToken,
        SiteId.linuxdo => s.linuxdoLoggedIn ? 'signed-in' : '',
        SiteId.juejin => s.juejinCookie,
      }));
  return Snapshots.fingerprint(credential);
});

// ---------- feed ----------

class FeedState {
  const FeedState({
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
    this.moreError,
    this.savedAt,
    this.refreshing = false,
    this.refreshError,
  });
  final List<TopicSummary> items;
  final String? nextCursor;
  final bool loadingMore;
  final String? moreError;

  /// When the list on screen was saved, while it is a copy from disk rather
  /// than what the site said just now.
  final DateTime? savedAt;

  /// Whether the site is being asked for a newer list than this one.
  final bool refreshing;

  /// Why the last attempt at a newer list did not land. What is on screen is
  /// what was there before.
  final String? refreshError;

  bool get hasMore => nextCursor != null;

  FeedState copyWith({
    List<TopicSummary>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
    String? moreError,
    bool clearError = false,
    bool? refreshing,
    String? refreshError,
  }) =>
      FeedState(
        items: items ?? this.items,
        nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
        loadingMore: loadingMore ?? this.loadingMore,
        moreError: clearError ? null : (moreError ?? this.moreError),
        savedAt: savedAt,
        refreshing: refreshing ?? this.refreshing,
        refreshError: refreshError ?? this.refreshError,
      );
}

class FeedNotifier extends FamilyAsyncNotifier<FeedState, FeedKey> {
  late ForumSource _source;
  late String _reader;
  late Future<List<Section>> _sections;

  /// Which build is current. A newer list arriving for a build since
  /// replaced — the credentials changed under it — is dropped.
  int _generation = 0;

  @override
  Future<FeedState> build(FeedKey arg) async {
    final generation = ++_generation;
    _source = ref.watch(sourceProvider(arg.site));
    _reader = ref.watch(readerProvider(arg.site));
    // Asked for but not waited on: a saved list can go up before the site
    // has said which boards it has.
    _sections = ref.watch(sectionsProvider(arg.site).future);
    final saved = await Snapshots.instance.loadFeed(arg, _reader);
    if (saved == null) return _load();
    // The copy goes up now; the site is asked behind it, and its answer
    // replaces the copy when it comes.
    Future.microtask(() => _revalidate(generation));
    return FeedState(
      items: _dedupe(saved.items),
      nextCursor: saved.nextCursor,
      savedAt: saved.savedAt,
      refreshing: true,
    );
  }

  Future<Section> _section() async {
    final sections = await _sections;
    return sections.firstWhere((s) => s.id == arg.sectionId,
        orElse: () => Section(id: arg.sectionId, title: arg.sectionId));
  }

  Future<FeedState> _load() async {
    final page = await _page();
    // A search is asked afresh every time; only a board is worth keeping.
    if (searchQueryOf(arg.sectionId) == null) {
      unawaited(Snapshots.instance.saveFeed(arg, _reader, page));
    }
    return FeedState(items: _dedupe(page.items), nextCursor: page.nextCursor);
  }

  Future<void> _revalidate(int generation) async {
    try {
      final fresh = await _load();
      if (generation != _generation) return;
      state = AsyncData(fresh);
    } catch (e) {
      if (generation != _generation) return;
      final cur = state.valueOrNull;
      if (cur == null) return;
      state = AsyncData(
          cur.copyWith(refreshing: false, refreshError: errorText(e)));
    }
  }

  /// Asks the site again. A list already on screen stays there if it
  /// cannot, with the reason beside it.
  Future<void> refresh() async {
    final generation = _generation;
    final cur = state.valueOrNull;
    state = const AsyncLoading<FeedState>().copyWithPrevious(state);
    try {
      final fresh = await _load();
      if (generation == _generation) state = AsyncData(fresh);
    } catch (e, st) {
      if (generation != _generation) return;
      state = cur == null || cur.items.isEmpty
          ? AsyncError(e, st)
          : AsyncData(FeedState(
              items: cur.items,
              nextCursor: cur.nextCursor,
              savedAt: cur.savedAt,
              refreshError: errorText(e),
            ));
    }
  }

  Future<void> loadMore() async {
    final cur = state.valueOrNull;
    if (cur == null || !cur.hasMore || cur.loadingMore) return;
    state = AsyncData(cur.copyWith(loadingMore: true, clearError: true));
    try {
      final page = await _page(cursor: cur.nextCursor);
      state = AsyncData(cur.copyWith(
        items: _dedupe([...cur.items, ...page.items]),
        nextCursor: page.nextCursor,
        clearCursor: !page.hasMore,
        loadingMore: false,
      ));
    } catch (e) {
      state = AsyncData(cur.copyWith(loadingMore: false, moreError: '$e'));
    }
  }

  /// A page of the board — or of the search, for a section that is one.
  Future<PageResult<TopicSummary>> _page({String? cursor}) async {
    if (searchQueryOf(arg.sectionId) case final query?) {
      final search = _source.search;
      if (search == null) throw Exception('${_source.name} 不能在应用里搜索');
      return search(query, cursor: cursor);
    }
    return _source.fetchTopics(await _section(), cursor: cursor);
  }

  List<TopicSummary> _dedupe(List<TopicSummary> items) {
    final seen = <String>{};
    return [
      for (final t in items)
        if (seen.add(t.id)) t,
    ];
  }
}

final feedProvider =
    AsyncNotifierProvider.family<FeedNotifier, FeedState, FeedKey>(
        FeedNotifier.new);

/// The feed as the list shows it: without the topics the reader has blocked.
///
/// Filtered here rather than in the feed itself, so that blocking or
/// unblocking something takes effect on what is already loaded instead of
/// fetching it all again.
final visibleFeedProvider =
    Provider.family<AsyncValue<FeedState>, FeedKey>((ref, key) {
  final feed = ref.watch(feedProvider(key));
  final blocks = ref.watch(settingsProvider.select((s) => s.blocks));
  if (blocks.isEmpty) return feed;
  return feed.whenData((state) => state.copyWith(
        items: [
          for (final t in state.items)
            if (!blocks.blocks(t)) t,
        ],
      ));
});

// ---------- topic detail ----------

/// A thread's opening post: from the site, and saved as it arrives.
///
/// When the site cannot be reached, the copy saved last time is shown in its
/// place, marked with when it was saved. A site that answered and said no —
/// sign in first — is taken at its word instead: an old copy would hide the
/// one thing the reader can do about it.
final topicDetailProvider =
    FutureProvider.family<TopicDetail, TopicRef>((ref, r) async {
  final source = ref.watch(sourceProvider(r.site));
  final reader = ref.watch(readerProvider(r.site));
  try {
    final detail = await source.fetchTopic(r.id);
    unawaited(Snapshots.instance.saveTopic(detail, reader));
    return detail;
  } on AuthRequiredException {
    rethrow;
  } catch (_) {
    final saved = await Snapshots.instance.loadTopic(r, reader);
    if (saved == null) rethrow;
    return saved;
  }
});

class RepliesState {
  const RepliesState({
    required this.items,
    this.nextCursor,
    this.total,
    this.loadingMore = false,
    this.moreError,
    this.sent = const [],
  });
  final List<Reply> items;
  final String? nextCursor;
  final int? total;
  final bool loadingMore;
  final String? moreError;

  /// Replies written from here, which stay at the end of the thread.
  ///
  /// Held apart from [items] because a thread arrives a page at a time: put
  /// in with the page, the next page — older posts — would be drawn after
  /// them.
  final List<Reply> sent;

  bool get hasMore => nextCursor != null;

  /// The thread as it should be read: what has been loaded, then whatever the
  /// reader has just written.
  List<Reply> get all => sent.isEmpty ? items : [...items, ...sent];
}

class RepliesNotifier extends FamilyAsyncNotifier<RepliesState, TopicRef> {
  late ForumSource _source;

  @override
  Future<RepliesState> build(TopicRef arg) async {
    _source = ref.watch(sourceProvider(arg.site));
    final reader = ref.watch(readerProvider(arg.site));
    // Make sure the topic itself is loaded first so sources can share state.
    await ref.watch(topicDetailProvider(arg).future);
    // The first page is saved with the post, and stands in for it the same
    // way; the pages after it are only ever the site's.
    try {
      final page = await _source.fetchReplies(arg.id);
      unawaited(Snapshots.instance.saveReplies(arg, reader, page));
      return RepliesState(
          items: page.items, nextCursor: page.nextCursor, total: page.total);
    } on AuthRequiredException {
      rethrow;
    } catch (_) {
      final saved = await Snapshots.instance.loadReplies(arg, reader);
      if (saved == null) rethrow;
      return RepliesState(
          items: saved.items, nextCursor: saved.nextCursor, total: saved.total);
    }
  }

  Future<void> loadMore() async {
    final cur = state.valueOrNull;
    if (cur == null || !cur.hasMore || cur.loadingMore) return;
    state = AsyncData(RepliesState(
        items: cur.items,
        nextCursor: cur.nextCursor,
        total: cur.total,
        sent: cur.sent,
        loadingMore: true));
    try {
      final page = await _source.fetchReplies(arg.id, cursor: cur.nextCursor);
      state = AsyncData(RepliesState(
        items: [...cur.items, ...page.items],
        nextCursor: page.nextCursor,
        total: page.total ?? cur.total,
        sent: cur.sent,
      ));
    } catch (e) {
      state = AsyncData(RepliesState(
          items: cur.items,
          nextCursor: cur.nextCursor,
          total: cur.total,
          sent: cur.sent,
          moreError: '$e'));
    }
  }

  /// Puts a reply the reader has just written at the end of the thread.
  ///
  /// Rather than reloading: they are at the bottom of something they scrolled
  /// through, and a reload would take them back to its first page with their
  /// own words the part not loaded. The count moves with it, since the forum
  /// now holds one more than it said.
  /// Puts a like back into the thread it belongs to.
  ///
  /// The list is what a tile is drawn from, and a tile scrolled out of sight
  /// is rebuilt from it — without this, the heart someone filled would come
  /// back empty the next time they scrolled past.
  void replaceLike(String replyId, LikeState like) {
    final cur = state.valueOrNull;
    if (cur == null) return;
    List<Reply> swap(List<Reply> list) => [
          for (final reply in list)
            reply.id == replyId ? reply.withLike(like) : reply,
        ];
    state = AsyncData(RepliesState(
      items: swap(cur.items),
      nextCursor: cur.nextCursor,
      total: cur.total,
      sent: swap(cur.sent),
    ));
  }

  /// False when there is no thread on screen to put it in — the caller then
  /// has nothing to preserve and can simply reload.
  bool appendSent(Reply reply) {
    final cur = state.valueOrNull;
    if (cur == null) return false;
    state = AsyncData(RepliesState(
      items: cur.items,
      nextCursor: cur.nextCursor,
      total: cur.total == null ? null : cur.total! + 1,
      sent: [...cur.sent, reply],
    ));
    return true;
  }
}

final repliesProvider =
    AsyncNotifierProvider.family<RepliesNotifier, RepliesState, TopicRef>(
        RepliesNotifier.new);
