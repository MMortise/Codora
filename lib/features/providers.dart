import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/forum_source.dart';
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
    // A site's hidden WebView holds the old cookies, so drop it when its
    // credentials change.
    if (next.linuxdoCookie != prev.linuxdoCookie ||
        next.linuxdoUserAgent != prev.linuxdoUserAgent) {
      await WebViewFetcher.instance.reset(Uri.parse('https://linux.do'));
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
  });
  final List<Reply> items;
  final String? nextCursor;
  final int? total;
  final bool loadingMore;
  final String? moreError;
  bool get hasMore => nextCursor != null;
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
        loadingMore: true));
    try {
      final page = await _source.fetchReplies(arg.id, cursor: cur.nextCursor);
      state = AsyncData(RepliesState(
        items: [...cur.items, ...page.items],
        nextCursor: page.nextCursor,
        total: page.total ?? cur.total,
      ));
    } catch (e) {
      state = AsyncData(RepliesState(
          items: cur.items,
          nextCursor: cur.nextCursor,
          total: cur.total,
          moreError: '$e'));
    }
  }
}

final repliesProvider =
    AsyncNotifierProvider.family<RepliesNotifier, RepliesState, TopicRef>(
        RepliesNotifier.new);
