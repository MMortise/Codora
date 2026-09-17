import 'dart:typed_data';

import '../core/forum_source.dart';
import '../core/http.dart';
import '../core/models.dart';
import '../core/util.dart';
import '../core/webview_fetcher.dart';

/// linux.do is a Discourse forum behind a Cloudflare managed challenge.
///
/// The clearance Cloudflare grants is bound to the browser that earned it, so
/// replaying its cookie from an HTTP client is refused. Every request here
/// therefore runs as same-origin `fetch` inside a hidden WebView that shares
/// the cookie jar with the visible verification page. The rest of the app
/// cannot tell the difference: this is still a plain [ForumSource].
class LinuxDoSource implements ForumSource {
  LinuxDoSource({required this.cookie, required this.userAgent});

  final String cookie;
  final String userAgent;

  static final _origin = Uri.parse('https://linux.do');

  Map<int, String> _categoryNames = {};
  final Map<String, _TopicStream> _streams = {};

  @override
  SiteId get id => SiteId.linuxdo;
  @override
  String get name => 'Linux.do';
  @override
  String get glyph => 'LD';
  @override
  String get iconAsset => 'assets/icons/linuxdo.png';
  @override
  Uri get homeUrl => Uri.parse('https://linux.do');
  @override
  String get accessNote => '整站有 Cloudflare 人机验证。用内置浏览器过一次验证（可以顺便登录），'
      '之后 Cookie 和该浏览器的 User-Agent 一起交给接口使用。';
  @override
  SiteAccess get access {
    if (!cookie.contains('cf_clearance=')) {
      return const SiteAccess(AccessLevel.blocked, '待验证');
    }
    return cookie.contains('_t=')
        ? const SiteAccess(AccessLevel.full, '已登录')
        : const SiteAccess(AccessLevel.limited, '已验证，未登录');
  }

  // Images are behind the same protection as the API, so they are fetched
  // through the WebView too rather than with headers a plain request sends.
  @override
  Map<String, String>? get imageHeaders => null;

  /// Whether an image has to be fetched through the browser.
  ///
  /// Only the forum's own domain sits behind the challenge. Uploads and emoji
  /// are served from ldstatic.com, which answers any client and sends
  /// `Access-Control-Allow-Origin: *`. Those must go over the normal network:
  /// fetching them from inside the linux.do page makes them cross-origin
  /// requests, which is how they ended up failing before.
  bool needsBrowser(Uri url) => url.host == _origin.host;

  @override
  Future<Uint8List>? Function(Uri url)? get imageLoader {
    if (cookie.isEmpty) return null;
    return (url) => needsBrowser(url)
        ? WebViewFetcher.instance.getBytes(_origin, url, userAgent: userAgent)
        : null;
  }

  @override
  Future<List<Section>> sections() async {
    const base = [
      Section(id: 'latest', title: '最新', subtitle: 'latest'),
      Section(id: 'hot', title: '热门', subtitle: 'hot'),
      Section(id: 'top:daily', title: '今日', subtitle: 'today'),
      Section(id: 'top:weekly', title: '本周', subtitle: 'this week'),
    ];
    if (cookie.isEmpty) return base;
    try {
      await _loadCategories();
      final res = await _get('/categories.json');
      final cats = ((res['category_list'] as Map?)?['categories'] as List? ??
              const [])
          .cast<Map>();
      return [
        ...base,
        for (final c in cats)
          Section(
              id: 'c:${c['slug']}:${c['id']}',
              title: '${c['name']}',
              subtitle: c['slug']?.toString(),
              group: '分类'),
      ];
    } catch (_) {
      return base;
    }
  }

  @override
  Future<PageResult<TopicSummary>> fetchTopics(Section section,
      {String? cursor}) async {
    _requireCookie();
    final page = int.tryParse(cursor ?? '') ?? 0;
    final String path;
    final query = <String, String>{'page': '$page'};
    if (section.id == 'latest') {
      path = '/latest.json';
    } else if (section.id == 'hot') {
      path = '/hot.json';
    } else if (section.id.startsWith('top:')) {
      path = '/top.json';
      query['period'] = section.id.substring(4);
    } else {
      final parts = section.id.split(':');
      path = '/c/${parts[1]}/${parts[2]}/l/latest.json';
    }
    if (_categoryNames.isEmpty) await _loadCategories();
    final res = await _get(path, query: query);
    final users = <int, Map>{
      for (final u in (res['users'] as List? ?? const []).cast<Map>())
        asInt(u['id'])!: u,
    };
    final tl = res['topic_list'] as Map? ?? const {};
    final topics = (tl['topics'] as List? ?? const []).cast<Map>();
    final items = [for (final t in topics) _mapTopic(t, users)];
    return PageResult(
      items: items,
      nextCursor: tl['more_topics_url'] != null ? '${page + 1}' : null,
    );
  }

  @override
  Future<TopicDetail> fetchTopic(String topicId) async {
    _requireCookie();
    if (_categoryNames.isEmpty) await _loadCategories();
    final res = await _get('/t/$topicId.json');
    final stream = _TopicStream.from(res);
    _streams[topicId] = stream;
    final first = stream.loadedPosts.isEmpty ? const {} : stream.loadedPosts.first;
    final details = res['details'] as Map? ?? const {};
    final creator = details['created_by'] as Map?;
    return TopicDetail(
      site: id,
      id: topicId,
      title: '${res['title']}',
      url: 'https://linux.do/t/${res['slug']}/$topicId',
      content: '${first['cooked'] ?? ''}',
      author: creator != null ? _author(creator) : _postAuthor(first),
      sectionLabel: _categoryNames[asInt(res['category_id'])],
      replyCount: (asInt(res['posts_count']) ?? 1) - 1,
      viewCount: asInt(res['views']),
      likeCount: asInt(res['like_count']),
      createdAt: fromIso(res['created_at']),
    );
  }

  @override
  Future<PageResult<Reply>> fetchReplies(String topicId,
      {String? cursor}) async {
    _requireCookie();
    var stream = _streams[topicId];
    if (stream == null) {
      final res = await _get('/t/$topicId.json');
      stream = _TopicStream.from(res);
      _streams[topicId] = stream;
    }
    final start = int.tryParse(cursor ?? '') ?? 1; // index into stream ids
    List<Map> posts;
    if (cursor == null) {
      posts = stream.loadedPosts.skip(1).toList();
    } else {
      final ids = stream.ids.skip(start).take(20).toList();
      if (ids.isEmpty) return const PageResult(items: []);
      final qs = ids.map((i) => 'post_ids[]=$i').join('&');
      final res = await _get('/t/$topicId/posts.json?$qs');
      posts = ((res['post_stream'] as Map?)?['posts'] as List? ?? const [])
          .cast<Map>();
    }
    final consumed = cursor == null ? stream.loadedPosts.length : start + posts.length;
    return PageResult(
      items: [for (final p in posts) _mapPost(p)],
      nextCursor: consumed < stream.ids.length ? '$consumed' : null,
      total: stream.ids.length - 1,
    );
  }

  @override
  String? topicIdFromUrl(Uri uri) {
    if (uri.host != 'linux.do' && !uri.host.endsWith('.linux.do')) return null;
    final m = RegExp(r'^/t/(?:[^/]+/)?(\d+)').firstMatch(uri.path);
    return m?.group(1);
  }

  Future<void> _loadCategories() async {
    try {
      final res = await _get('/categories.json');
      final cats = ((res['category_list'] as Map?)?['categories'] as List? ??
              const [])
          .cast<Map>();
      _categoryNames = {
        for (final c in cats) asInt(c['id'])!: '${c['name']}',
      };
    } on AuthRequiredException {
      rethrow;
    } catch (_) {}
  }

  TopicSummary _mapTopic(Map t, Map<int, Map> users) {
    final posters = (t['posters'] as List? ?? const []).cast<Map>();
    Map? op;
    for (final p in posters) {
      if ('${p['description']}'.contains('Original Poster')) {
        op = users[asInt(p['user_id'])];
        break;
      }
    }
    op ??= posters.isNotEmpty ? users[asInt(posters.first['user_id'])] : null;
    final tid = '${t['id']}';
    return TopicSummary(
      site: id,
      id: tid,
      title: '${t['fancy_title'] ?? t['title']}',
      url: 'https://linux.do/t/${t['slug']}/$tid',
      excerpt: htmlToPreview(t['excerpt']?.toString()),
      author: op == null ? null : _author(op),
      sectionLabel: _categoryNames[asInt(t['category_id'])],
      replyCount: (asInt(t['posts_count']) ?? 1) - 1,
      viewCount: asInt(t['views']),
      likeCount: asInt(t['like_count']),
      createdAt: fromIso(t['created_at']),
      lastActiveAt: fromIso(t['bumped_at'] ?? t['last_posted_at']),
      coverUrl: t['image_url']?.toString(),
    );
  }

  Reply _mapPost(Map p) {
    int? likes = asInt(p['like_count']);
    if (likes == null) {
      for (final a in (p['actions_summary'] as List? ?? const []).cast<Map>()) {
        if (asInt(a['id']) == 2) likes = asInt(a['count']);
      }
    }
    return Reply(
      id: '${p['id']}',
      content: '${p['cooked'] ?? ''}',
      author: _postAuthor(p),
      createdAt: fromIso(p['created_at']),
      floor: asInt(p['post_number']),
      likeCount: likes,
    );
  }

  Author _author(Map u) => Author(
        name: '${u['username']}',
        avatarUrl: _avatar(u['avatar_template']?.toString()),
        url: 'https://linux.do/u/${u['username']}',
        tagline: u['name']?.toString(),
      );

  Author? _postAuthor(Map p) => p['username'] == null ? null : _author(p);

  String? _avatar(String? template) {
    if (template == null || template.isEmpty) return null;
    final u = template.replaceAll('{size}', '96');
    return u.startsWith('http') ? u : 'https://linux.do$u';
  }

  void _requireCookie() {
    if (!cookie.contains('cf_clearance=')) {
      throw AuthRequiredException(
          id, '需要先完成 linux.do 的人机验证', AuthRecovery.browser);
    }
  }

  Future<Map> _get(String path, {Map<String, String>? query}) async {
    final target = query == null || query.isEmpty
        ? path
        : Uri.parse(path).replace(
            queryParameters: {
              ...Uri.parse(path).queryParameters,
              ...query,
            },
          ).toString();

    final Object? data;
    try {
      data = await WebViewFetcher.instance
          .getJson(_origin, target, userAgent: userAgent);
    } on WebViewFetchException catch (e) {
      if (e.isChallenge) {
        throw AuthRequiredException(
            id, 'linux.do 的人机验证已过期', AuthRecovery.browser);
      }
      if (e.status == 404) throw Exception('这个内容不存在，或者没有权限看');
      if (e.status == 429) throw Exception('请求太频繁了，等一会儿再试');
      if (e.status == 0) throw Exception('连不上 linux.do：${e.body}');
      throw Exception('linux.do 返回了 HTTP ${e.status}');
    }
    if (data is! Map) throw Exception('linux.do 返回了意外的数据');
    return data;
  }
}

class _TopicStream {
  _TopicStream(this.ids, this.loadedPosts);
  final List<int> ids;
  final List<Map> loadedPosts;

  factory _TopicStream.from(Map topicJson) {
    final ps = topicJson['post_stream'] as Map? ?? const {};
    final ids = (ps['stream'] as List? ?? const []).map((e) => asInt(e)!).toList();
    final posts = (ps['posts'] as List? ?? const []).cast<Map>();
    return _TopicStream(ids, posts);
  }
}
