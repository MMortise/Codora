import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/disk_cache.dart';
import '../core/forum_source.dart';
import '../core/linuxdo_session.dart';
import '../core/models.dart';
import '../core/read_log.dart';
import '../core/settings.dart';
import '../core/webview_fetcher.dart';
import '../sources/juejin_source.dart';
import '../sources/linuxdo_source.dart';
import '../sources/v2ex_source.dart';

enum NavTarget { v2ex, linuxdo, juejin, settings }

extension NavTargetX on NavTarget {
  SiteId? get site => switch (this) {
        NavTarget.v2ex => SiteId.v2ex,
        NavTarget.linuxdo => SiteId.linuxdo,
        NavTarget.juejin => SiteId.juejin,
        NavTarget.settings => null,
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
final navProvider = StateProvider<NavTarget>((_) => NavTarget.v2ex);

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

  Future<void> clear() async {
    state = state.cleared();
    ReadLog.bootstrap = state;
    await state.save();
  }
}

final readLogProvider =
    NotifierProvider<ReadLogNotifier, ReadLog>(ReadLogNotifier.new);

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

final selectedSectionProvider =
    StateProvider.family<String?, SiteId>((_, _) => null);

/// Stack of opened topics in the detail pane; last is the visible one.
final detailStackProvider =
    StateProvider.family<List<TopicRef>, SiteId>((_, _) => const []);

// ---------- feed ----------

class FeedState {
  const FeedState({
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
    this.moreError,
  });
  final List<TopicSummary> items;
  final String? nextCursor;
  final bool loadingMore;
  final String? moreError;
  bool get hasMore => nextCursor != null;

  FeedState copyWith({
    List<TopicSummary>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
    String? moreError,
    bool clearError = false,
  }) =>
      FeedState(
        items: items ?? this.items,
        nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
        loadingMore: loadingMore ?? this.loadingMore,
        moreError: clearError ? null : (moreError ?? this.moreError),
      );
}

class FeedNotifier extends FamilyAsyncNotifier<FeedState, FeedKey> {
  late ForumSource _source;
  late Section _section;

  @override
  Future<FeedState> build(FeedKey arg) async {
    _source = ref.watch(sourceProvider(arg.site));
    final sections = await ref.watch(sectionsProvider(arg.site).future);
    _section = sections.firstWhere((s) => s.id == arg.sectionId,
        orElse: () => Section(id: arg.sectionId, title: arg.sectionId));
    return _load();
  }

  Future<FeedState> _load() async {
    final page = await _source.fetchTopics(_section);
    return FeedState(items: _dedupe(page.items), nextCursor: page.nextCursor);
  }

  Future<void> refresh() async {
    state = const AsyncLoading<FeedState>().copyWithPrevious(state);
    state = await AsyncValue.guard(_load);
  }

  Future<void> loadMore() async {
    final cur = state.valueOrNull;
    if (cur == null || !cur.hasMore || cur.loadingMore) return;
    state = AsyncData(cur.copyWith(loadingMore: true, clearError: true));
    try {
      final page = await _source.fetchTopics(_section, cursor: cur.nextCursor);
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

// ---------- topic detail ----------

final topicDetailProvider =
    FutureProvider.family<TopicDetail, TopicRef>((ref, r) {
  return ref.watch(sourceProvider(r.site)).fetchTopic(r.id);
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
    // Make sure the topic itself is loaded first so sources can share state.
    await ref.watch(topicDetailProvider(arg).future);
    final page = await _source.fetchReplies(arg.id);
    return RepliesState(
        items: page.items, nextCursor: page.nextCursor, total: page.total);
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
