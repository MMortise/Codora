import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../core/forum_source.dart';
import '../core/http.dart';
import '../core/models.dart';

class JuejinSource implements ForumSource {
  JuejinSource({this.cookie = ''})
      : _dio = buildDio(baseUrl: 'https://api.juejin.cn', headers: {
          'Content-Type': 'application/json',
          'Origin': 'https://juejin.cn',
          'Referer': 'https://juejin.cn/',
          if (cookie.isNotEmpty) 'Cookie': cookie,
        });

  final String cookie;
  final Dio _dio;
  static const _q = {'aid': '2608', 'uuid': '7350012345678901234'};

  @override
  SiteId get id => SiteId.juejin;
  @override
  String get name => '掘金';
  @override
  String get glyph => '掘';
  @override
  String get iconAsset => 'assets/icons/juejin.png';
  @override
  Uri get homeUrl => Uri.parse('https://juejin.cn');
  @override
  String get accessNote => '匿名即可读推荐、最新、热榜、分类和评论。填入 Cookie 后推荐会按你的账号来。';
  @override
  SiteImages get images => SiteImages.plain;

  // 掘金's own API describes the signed-in reader, but the rail card is
  // built around a forum inbox and 掘金 keeps its notifications somewhere
  // else entirely. Nothing to show here yet.
  @override
  Future<Member> Function()? get member => null;

  // Reading only. 掘金's write endpoints want a signature the app does not
  // have any way to produce.
  @override
  SendReply? get reply => null;

  @override
  ActOnLike? get like => null;

  @override
  UploadImage? get uploadImage => null;

  @override
  SiteAccess get access => cookie.isEmpty
      ? const SiteAccess(AccessLevel.open, '匿名浏览')
      : const SiteAccess(AccessLevel.full, '已登录');

  @override
  Future<List<Section>> sections() async {
    final base = [
      const Section(id: 'recommend', title: '推荐', subtitle: 'for you'),
      const Section(id: 'latest', title: '最新', subtitle: 'latest'),
      const Section(id: 'hot', title: '热榜', subtitle: 'ranking'),
    ];
    try {
      final res = await _get('/tag_api/v1/query_category_briefs');
      final cats = (res['data'] as List? ?? const []).cast<Map>();
      return [
        ...base,
        for (final c in cats)
          Section(
              id: 'cate:${c['category_id']}',
              title: '${c['category_name']}',
              subtitle: c['category_url']?.toString(),
              group: '分类'),
      ];
    } catch (_) {
      return base;
    }
  }

  @override
  Future<PageResult<TopicSummary>> fetchTopics(Section section,
      {String? cursor}) async {
    if (section.id == 'hot') {
      final res = await _get('/content_api/v1/content/article_rank',
          query: {'category_id': '1', 'type': 'hot'});
      final list = (res['data'] as List? ?? const []).cast<Map>();
      return PageResult(items: [
        for (final it in list) _mapRank(it),
      ]);
    }
    final Map<String, dynamic> body;
    final String path;
    if (section.id.startsWith('cate:')) {
      path = '/recommend_api/v1/article/recommend_cate_feed';
      body = {
        'cate_id': section.id.substring(5),
        'id_type': 2,
        'sort_type': 200,
        'cursor': cursor ?? '0',
        'limit': 20,
      };
    } else {
      path = '/recommend_api/v1/article/recommend_all_feed';
      body = {
        'id_type': 2,
        'client_type': 2608,
        'sort_type': section.id == 'latest' ? 300 : 200,
        'cursor': cursor ?? '0',
        'limit': 20,
      };
    }
    final res = await _post(path, body);
    final list = (res['data'] as List? ?? const []).cast<Map>();
    final items = <TopicSummary>[];
    for (final it in list) {
      // recommend_all_feed wraps articles as {item_type: 2, item_info: {...}}
      // while recommend_cate_feed returns the article object directly.
      if (it['article_info'] is Map) {
        items.add(_mapArticle(it));
      } else if (it['item_type'] == 2 && it['item_info'] is Map) {
        items.add(_mapArticle(it['item_info'] as Map));
      }
    }
    final hasMore = res['has_more'] == true;
    return PageResult(
      items: items,
      nextCursor: hasMore ? res['cursor']?.toString() : null,
    );
  }

  @override
  Future<TopicDetail> fetchTopic(String topicId) async {
    final res = await _post('/content_api/v1/article/detail', {
      'article_id': topicId,
      'client_type': 2608,
      'need_theme': true,
    });
    final data = res['data'] as Map;
    final a = data['article_info'] as Map;
    final u = data['author_user_info'] as Map?;
    final cat = data['category'] as Map?;
    // Juejin fills in `mark_content` (markdown) and leaves `content` empty for
    // every article we have seen; the HTML field is only a fallback.
    final html = (a['content'] as String?) ?? '';
    final markdown = _stripFrontMatter((a['mark_content'] as String?) ?? '');
    final useMarkdown = html.trim().isEmpty && markdown.trim().isNotEmpty;
    return TopicDetail(
      site: id,
      id: topicId,
      title: '${a['title']}',
      url: 'https://juejin.cn/post/$topicId',
      content: useMarkdown ? markdown : html,
      format: useMarkdown ? BodyFormat.markdown : BodyFormat.html,
      author: u == null ? null : _author(u),
      sectionLabel: cat?['category_name']?.toString(),
      replyCount: asInt(a['comment_count']),
      viewCount: asInt(a['view_count']),
      likeCount: asInt(a['digg_count']),
      createdAt: fromUnixSeconds(a['ctime']),
    );
  }

  @override
  Future<PageResult<Reply>> fetchReplies(String topicId,
      {String? cursor}) async {
    final res = await _post('/interact_api/v1/comment/list', {
      'client_type': 2608,
      'item_id': topicId,
      'item_type': 2,
      'cursor': cursor ?? '0',
      'limit': 20,
      'sort_type': 0,
    });
    final list = (res['data'] as List? ?? const []).cast<Map>();
    final items = <Reply>[];
    for (final c in list) {
      final info = c['comment_info'] as Map? ?? const {};
      final user = c['user_info'] as Map?;
      final replies = (c['reply_infos'] as List? ?? const []).cast<Map>();
      items.add(Reply(
        id: '${info['comment_id'] ?? c['comment_id']}',
        content: _textToHtml('${info['comment_content'] ?? ''}'),
        author: user == null ? null : _author(user),
        createdAt: fromUnixSeconds(info['ctime']),
        likeCount: asInt(info['digg_count']),
        children: [
          for (final r in replies)
            Reply(
              id: '${r['reply_id']}',
              content: _textToHtml(
                  '${(r['reply_info'] as Map?)?['reply_content'] ?? ''}'),
              author: r['user_info'] is Map ? _author(r['user_info'] as Map) : null,
              createdAt: fromUnixSeconds((r['reply_info'] as Map?)?['ctime']),
              likeCount: asInt((r['reply_info'] as Map?)?['digg_count']),
            ),
        ],
      ));
    }
    final hasMore = res['has_more'] == true;
    return PageResult(
      items: items,
      nextCursor: hasMore ? res['cursor']?.toString() : null,
      total: asInt(res['count']),
    );
  }

  // Juejin's own search, the one its site calls, limited to articles.
  @override
  SearchTopics? get search => _search;

  @override
  Uri? searchPage(String query) => null;

  Future<PageResult<TopicSummary>> _search(String query,
      {String? cursor}) async {
    final res = await _post('/search_api/v1/search', {
      'cursor': cursor ?? '0',
      'key_word': query,
      'id_type': 2,
      'limit': 20,
      'search_type': 0,
      'sort_type': 0,
      'version': 1,
    });
    return parseSearch(res);
  }

  /// A page of search results. Each wraps the same article object the feeds
  /// hand back, as `result_model`; anything else it may carry — users, tags —
  /// is not a topic and is passed over.
  @visibleForTesting
  PageResult<TopicSummary> parseSearch(Map res) {
    final items = <TopicSummary>[];
    for (final hit in (res['data'] as List? ?? const []).whereType<Map>()) {
      final model = hit['result_model'];
      if (model is Map && model['article_info'] is Map) {
        items.add(_mapArticle(model));
      }
    }
    return PageResult(
      items: items,
      nextCursor: res['has_more'] == true ? res['cursor']?.toString() : null,
    );
  }

  @override
  String? topicIdFromUrl(Uri uri) {
    if (!uri.host.endsWith('juejin.cn')) return null;
    final m = RegExp(r'^/post/(\d+)').firstMatch(uri.path);
    return m?.group(1);
  }

  TopicSummary _mapArticle(Map info) {
    final a = info['article_info'] as Map? ?? const {};
    final u = info['author_user_info'] as Map?;
    final cat = info['category'] as Map?;
    final articleId = '${info['article_id'] ?? a['article_id']}';
    final cover = a['cover_image']?.toString();
    final catName = cat?['category_name']?.toString();
    return TopicSummary(
      site: id,
      id: articleId,
      title: '${a['title']}',
      url: 'https://juejin.cn/post/$articleId',
      excerpt: a['brief_content']?.toString(),
      author: u == null ? null : _author(u),
      sectionLabel: (catName == null || catName.isEmpty) ? null : catName,
      replyCount: asInt(a['comment_count']),
      viewCount: asInt(a['view_count']),
      likeCount: asInt(a['digg_count']),
      createdAt: fromUnixSeconds(a['ctime']),
      coverUrl: (cover == null || cover.isEmpty) ? null : cover,
    );
  }

  TopicSummary _mapRank(Map it) {
    final c = it['content'] as Map? ?? const {};
    final au = it['author'] as Map?;
    final counter = it['content_counter'] as Map? ?? const {};
    final cid = '${c['content_id']}';
    return TopicSummary(
      site: id,
      id: cid,
      title: '${c['title']}',
      url: 'https://juejin.cn/post/$cid',
      excerpt: c['brief']?.toString(),
      author: au == null
          ? null
          : Author(
              name: '${au['name']}',
              avatarUrl: au['avatar']?.toString(),
              url: 'https://juejin.cn/user/${au['user_id']}'),
      replyCount: asInt(counter['comment_count']),
      viewCount: asInt(counter['view']),
      likeCount: asInt(counter['like']),
      createdAt: fromUnixSeconds(c['ctime']),
    );
  }

  Author _author(Map u) => Author(
        name: '${u['user_name']}',
        avatarUrl: u['avatar_large']?.toString(),
        url: 'https://juejin.cn/user/${u['user_id']}',
        tagline: [u['company'], u['job_title']]
            .where((e) => e != null && '$e'.isNotEmpty)
            .join(' · '),
      );

  /// Juejin markdown often starts with a `---` YAML block (theme/highlight).
  String _stripFrontMatter(String s) {
    final t = s.trimLeft();
    if (!t.startsWith('---')) return s;
    final end = t.indexOf(RegExp(r'\n---[ \t]*(\n|\$)'), 3);
    return end == -1 ? s : t.substring(t.indexOf('\n', end + 1) + 1);
  }

  String _textToHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('\n', '<br>');

  Future<Map> _get(String path, {Map<String, String>? query}) async {
    final res = await _dio.get(path, queryParameters: {..._q, ...?query});
    return _check(res);
  }

  Future<Map> _post(String path, Map<String, dynamic> body) async {
    final res = await _dio.post(path, queryParameters: _q, data: body);
    return _check(res);
  }

  Map _check(Response res) {
    final data = res.data;
    if (data is! Map) {
      throw Exception('掘金请求失败（HTTP ${res.statusCode}）');
    }
    final errNo = asInt(data['err_no']) ?? 0;
    if (errNo != 0) {
      throw Exception('掘金：${data['err_msg'] ?? '错误 $errNo'}');
    }
    return data;
  }
}
