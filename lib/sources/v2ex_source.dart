import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/parser.dart' as html_parser;

import '../core/forum_source.dart';
import '../core/http.dart';
import '../core/models.dart';
import '../core/proxy.dart';
import '../core/settings.dart';
import '../core/util.dart';

class V2exSource implements ForumSource {
  factory V2exSource({String token = '', String proxy = ''}) =>
      V2exSource._(token, SiteProxy.parse(proxy));

  // The address is parsed once and handed to both the client that uses it and
  // the field that reports whether there is one.
  V2exSource._(this.token, SiteProxy? proxy)
      : _proxy = proxy,
        _dio = buildDio(
          baseUrl: 'https://www.v2ex.com',
          proxy: proxy,
          headers: {'User-Agent': 'Codora/0.1 (+https://github.com/codora)'},
        );

  final String token;

  final SiteProxy? _proxy;
  final Dio _dio;

  @override
  SiteId get id => SiteId.v2ex;
  @override
  String get name => 'V2EX';
  @override
  String get glyph => 'V2';
  @override
  String get iconAsset => 'assets/icons/v2ex.png';
  @override
  Uri get homeUrl => Uri.parse('https://www.v2ex.com');
  @override
  String get accessNote => '匿名即可读最热、最新和节点。填入 Personal Access Token 后，'
      '节点列表改走 v2 接口并支持翻页。直连不通的网络，填个代理地址整站就都从那里走。';
  // Every picture under the V2EX tab, not only the ones on v2ex.com: posts
  // link attachments from imgur, sm.ms and whatever else the author used, and
  // a reader who needs a proxy to reach the forum usually needs it for those
  // too. Whether they actually take it is the reader's call, applied by
  // `siteImagesProvider` — it changes nothing about the feed, so it must not
  // rebuild this source.
  //
  // A rewriter only needs the address changed. A tunnel cannot work that way:
  // pictures are drawn by `Image.network`, which has its own HTTP client and
  // knows nothing about this one's proxy, so their bytes are fetched here
  // instead.
  @override
  late final SiteImages images = switch (_proxy) {
    null => SiteImages.plain,
    ProxyRewrite p => SiteImages(rewrite: p.apply),
    ProxyTunnel _ => SiteImages(loader: _fetchImage),
  };

  Future<Uint8List> _fetchImage(Uri url) async {
    final Response<List<int>> res;
    try {
      res = await _dio.getUri<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Accept': 'image/*,*/*'},
        ),
      );
    } on DioException catch (e) {
      throw Exception('图片没能通过代理加载：${e.message ?? e.type.name}');
    }
    final bytes = res.data;
    if ((res.statusCode ?? 0) >= 400 || bytes == null || bytes.isEmpty) {
      throw Exception('图片没能加载（HTTP ${res.statusCode}）');
    }
    return Uint8List.fromList(bytes);
  }
  // The v2 API is the only part of V2EX that answers as a person, and a token
  // is the only thing that opens it. Without one there is no profile to show,
  // so the rail offers no card.
  @override
  Future<Member> Function()? get member => token.isEmpty ? null : _fetchMember;

  // Reading only. The v2 API has no write side at all — replying on V2EX
  // needs a web session and the form's own once-off token.
  @override
  Future<Reply> Function(String, String)? get reply => null;

  // V2EX has no likes to give: it counts thanks, and sending one needs a web
  // session and the form's own token.
  @override
  Future<LikeState> Function(String, {required bool like})? get like => null;

  /// How long the card waits before saying so. [kMemberDeadline] is where
  /// the number is argued; it is named again here because the sentence below
  /// quotes it.
  static const memberDeadline = kMemberDeadline;

  Future<Member> _fetchMember() async {
    // Two independent reads, so the card waits for the slower of them rather
    // than for both in turn.
    //
    // `Future.wait` rather than the record form: a record's `.wait` reports
    // failure as a `ParallelWaitError`, which buries both the sentence the
    // source wrote and the fact that it was an auth failure at all — an
    // expired token would reach the card as `ParallelWaitError: …` with no
    // way to offer settings. This one rethrows the first error as thrown.
    final pair = await Future.wait([
      _get('/api/v2/member', bearer: true),
      _get('/api/v2/notifications', query: {'p': '1'}, bearer: true),
    ]).timeout(memberDeadline, onTimeout: () => throw slowMemberError());
    return parseMember(pair.first, pair.last);
  }

  /// Names whichever end went quiet, the same way [unreachableError] does for
  /// the feed. Built apart from being thrown so both shapes can be checked.
  @visibleForTesting
  AuthRequiredException slowMemberError() {
    final seconds = memberDeadline.inSeconds;
    if (_proxy == null) {
      return AuthRequiredException(
        id,
        'V2EX 没有回应',
        AuthRecovery.settings,
        hint: '个人信息 $seconds 秒没读回来。网络到 V2EX 这一段不通的话，'
            '到设置里给它填一个代理地址。',
      );
    }
    return AuthRequiredException(
      id,
      '代理没把个人信息带回来',
      AuthRecovery.settings,
      hint: '$seconds 秒没等到回应。代理本身可能连上了，但没有转发 V2EX 的接口。',
    );
  }

  /// Built apart from the request so both payloads can be checked without a
  /// network.
  @visibleForTesting
  static Member parseMember(dynamic profile, dynamic inbox) {
    final m = (profile as Map)['result'] as Map? ?? const {};
    final rows = ((inbox as Map)['result'] as List? ?? const []).cast<Map>();
    return Member(
      name: '${m['username']}',
      avatarUrl: _abs(m['avatar_large']?.toString()) ??
          _abs(m['avatar_normal']?.toString()),
      url: m['url']?.toString(),
      // V2EX has two of these: a one-liner shown beside the name and a longer
      // paragraph below it. Either may be blank, and the card has room for
      // one line, so whichever is filled in wins.
      tagline: _text(m['tagline']) ?? _text(m['bio']),
      number: asInt(m['id']),
      joinedAt: fromUnixSeconds(m['created']),
      badge: asInt(m['pro']) == 1 ? 'PRO' : null,
      notifications: [
        for (final n in rows)
          if (asInt(n['id']) case final id?)
            Notice(
              id: id,
              text: htmlToPreview(n['text']?.toString(), max: 70),
              createdAt: fromUnixSeconds(n['created']),
            ),
      ],
      // "Notifications 1-10/535" is the only place the API states how many
      // there are; the rows themselves are one page of ten.
      notificationTotal: asInt(RegExp(r'/(\d+)\s*$')
          .firstMatch('${inbox['message'] ?? ''}')
          ?.group(1)),
      notificationsUrl: Uri.parse('https://www.v2ex.com/notifications'),
      note: '金币、签到和收藏要网页登录才读得到，Token 读不到',
    );
  }

  /// Trimmed, with a blank string read as absent — V2EX fills unset profile
  /// fields with `""` rather than leaving them out.
  static String? _text(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  // How the site is being reached matters more here than what it is being
  // read as: without a reachable route there is nothing for a token to do.
  @override
  SiteAccess get access {
    final via = _proxy == null ? '直连' : '经代理';
    return token.isEmpty
        ? SiteAccess(AccessLevel.open, via)
        : SiteAccess(AccessLevel.full, '$via · Token');
  }

  static const _nodes = <(String, String)>[
    ('programmer', '程序员'),
    ('share', '分享发现'),
    ('create', '分享创造'),
    ('qna', '问与答'),
    ('career', '职场话题'),
    ('jobs', '酷工作'),
    ('apple', 'Apple'),
    ('macos', 'macOS'),
    ('python', 'Python'),
    ('fe', '前端开发'),
    ('go', 'Go'),
    ('all4all', '二手交易'),
  ];

  @override
  Future<List<Section>> sections() async => [
        const Section(id: 'all', title: '全部', subtitle: 'all'),
        const Section(id: 'hot', title: '最热', subtitle: 'hot'),
        const Section(id: 'latest', title: '最新', subtitle: 'latest'),
        for (final (name, title) in _nodes)
          Section(id: 'node:$name', title: title, subtitle: name, group: '节点'),
      ];

  @override
  Future<PageResult<TopicSummary>> fetchTopics(Section section,
      {String? cursor}) async {
    if (section.id == 'all') return _fetchAllTab();
    if (section.id == 'hot' || section.id == 'latest') {
      final res = await _get('/api/topics/${section.id}.json');
      return PageResult(items: _mapList(res));
    }
    final node = section.id.substring('node:'.length);
    if (token.isNotEmpty) {
      final page = int.tryParse(cursor ?? '') ?? 1;
      final res = await _get('/api/v2/nodes/$node/topics',
          query: {'p': '$page'}, bearer: true);
      final list = (res['result'] as List? ?? const []);
      final items = [for (final t in list) _mapTopic(t, nodeTitle: section.title)];
      return PageResult(
        items: items,
        nextCursor: items.length >= 20 ? '${page + 1}' : null,
      );
    }
    final res = await _get('/api/topics/show.json', query: {'node_name': node});
    return PageResult(items: _mapList(res));
  }

  /// V2EX's 全部 tab is the whole site ordered by latest reply. It has no JSON
  /// endpoint, so this reads the same page the site serves to a browser.
  /// Roughly 55 topics, one page only.
  Future<PageResult<TopicSummary>> _fetchAllTab() async {
    Response<String> res;
    try {
      res = await _dio.get<String>(
        '/',
        queryParameters: {'tab': 'all'},
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Accept': 'text/html,application/xhtml+xml',
            'User-Agent': kDesktopUserAgent,
          },
        ),
      );
    } on DioException catch (e) {
      res = e.response as Response<String>? ?? _unreachable(e);
    }
    final code = res.statusCode ?? 0;
    if (code == 403 || code == 429) {
      throw Exception('V2EX 限流了（HTTP $code），过一会儿再试');
    }
    if (code >= 400) throw Exception('V2EX 请求失败（HTTP $code）');

    final doc = html_parser.parse(res.data ?? '');
    final items = <TopicSummary>[];
    for (final el in doc.querySelectorAll('.cell.item')) {
      final link = el.querySelector('.item_title a');
      final href = link?.attributes['href'];
      if (link == null || href == null) continue;
      final match = RegExp(r'^/t/(\d+)').firstMatch(href);
      if (match == null) continue;

      final topicId = match.group(1)!;
      final node = el.querySelector('.topic_info a.node');
      final authorEl = el.querySelector('.topic_info strong a[href^="/member/"]');
      final avatar = el.querySelector('img.avatar')?.attributes['src'];
      final time = el.querySelector('.topic_info span[title]')?.attributes['title'];
      final count = el.querySelector('td[align="right"] a');
      final authorName = authorEl?.text.trim() ?? '';

      items.add(TopicSummary(
        site: id,
        id: topicId,
        title: link.text.trim(),
        url: 'https://www.v2ex.com/t/$topicId',
        author: authorName.isEmpty
            ? null
            : Author(
                name: authorName,
                // The page embeds the full-size avatar; the list draws it at
                // 18px, so ask for the small one instead of 55 large files.
                avatarUrl: _abs(avatar?.replaceFirst('_xlarge.', '_normal.')),
                url: 'https://www.v2ex.com/member/$authorName',
              ),
        sectionLabel: node?.text.trim(),
        replyCount: asInt(count?.text.trim()),
        lastActiveAt: _parsePageTime(time),
      ));
    }
    if (items.isEmpty) {
      throw Exception('没能从 V2EX 首页读出主题，页面结构可能变了');
    }
    return PageResult(items: items);
  }

  /// How long a hand-run test waits. Longer than the card's deadline: someone
  /// who pressed a button is waiting for the answer, and a route that is only
  /// slow is worth telling apart from one that is dead.
  static const probeDeadline = Duration(seconds: 12);

  /// Tries the smallest thing V2EX answers, and reports how long it took.
  ///
  /// Anonymous on purpose. The question is whether this route reaches V2EX at
  /// all, and sending the token would let an expired one read as a broken
  /// network. Throws with the reason when it does not get there.
  Future<Duration> probe() async {
    final clock = Stopwatch()..start();
    try {
      await _get('/api/topics/hot.json').timeout(probeDeadline);
    } on TimeoutException {
      throw Exception('超过 ${probeDeadline.inSeconds} 秒没有回应');
    }
    return clock.elapsed;
  }

  /// Drops the client and any connection it is holding. Only a source built
  /// for a single [probe] needs this; the ones behind the feed live as long
  /// as the settings they were built from.
  void close() => _dio.close(force: true);

  /// Turns a request that never got an answer into something to act on.
  ///
  /// V2EX does not answer from every network, and the symptom is a connection
  /// that simply never completes. Reporting that as "网络错误" leaves the
  /// reader with nowhere to go, so it is named for what it usually is and
  /// points at the setting that fixes it. Once a proxy is set the same failure
  /// means something else — the proxy is the part that is down — so it is
  /// reported as that instead of blaming V2EX.
  Never _unreachable(DioException e) => throw unreachableError(e);

  /// Built separately from being thrown so both shapes of it can be checked
  /// without a network.
  @visibleForTesting
  AuthRequiredException unreachableError(DioException e) {
    if (_proxy == null) {
      return AuthRequiredException(
        id,
        '连不上 V2EX',
        AuthRecovery.settings,
        hint: '有的网络能直连 V2EX，有的不能。连不上的话，'
            '到设置里给它填一个代理地址，整站就都从那里走。',
      );
    }
    return AuthRequiredException(
      id,
      '代理没能连上 V2EX',
      AuthRecovery.settings,
      hint: '代理没有响应（${e.message ?? e.type.name}）。到设置里确认代理地址还能用。',
    );
  }

  /// The page writes times as `2026-09-17 09:48:32 +08:00`, which needs the
  /// space before the offset removed before Dart will parse it.
  DateTime? _parsePageTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw
        .replaceFirst(' ', 'T')
        .replaceAll(RegExp(r'\s+(?=[+-]\d{2}:\d{2}$)'), ''));
  }

  @override
  Future<TopicDetail> fetchTopic(String topicId) async {
    final res = await _get('/api/topics/show.json', query: {'id': topicId});
    final list = res as List;
    if (list.isEmpty) throw Exception('主题不存在或已被删除');
    final t = list.first as Map;
    final member = t['member'] as Map?;
    final node = t['node'] as Map?;
    final rendered = (t['content_rendered'] as String?) ?? '';
    return TopicDetail(
      site: id,
      id: '${t['id']}',
      title: '${t['title']}',
      url: '${t['url']}',
      content: rendered.isNotEmpty ? rendered : _escape('${t['content'] ?? ''}'),
      author: member == null ? null : _author(member),
      sectionLabel: node?['title']?.toString(),
      replyCount: asInt(t['replies']),
      createdAt: fromUnixSeconds(t['created']),
    );
  }

  /// V2EX's reply API lags roughly an hour behind: a thread posted minutes ago
  /// reports its reply count correctly but hands back an empty list. The topic
  /// page is current, so replies are read from there and the API is kept only
  /// as a fallback for when the page cannot be parsed.
  @override
  Future<PageResult<Reply>> fetchReplies(String topicId,
      {String? cursor}) async {
    try {
      final fromPage = await _scrapeReplies(topicId);
      if (fromPage.isNotEmpty) return PageResult(items: fromPage);
    } catch (_) {
      // Fall through to the API below.
    }
    final res = await _get('/api/replies/show.json', query: {'topic_id': topicId});
    return PageResult(
        items: _buildReplies((res as List).cast<Map<String, Object?>>()));
  }

  /// Reads the replies off the topic page, which is always up to date.
  Future<List<Reply>> _scrapeReplies(String topicId) async {
    Response<String> res;
    try {
      res = await _dio.get<String>(
        '/t/$topicId',
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Accept': 'text/html,application/xhtml+xml',
            'User-Agent': kDesktopUserAgent,
          },
        ),
      );
    } on DioException catch (e) {
      res = e.response as Response<String>? ?? _unreachable(e);
    }
    if ((res.statusCode ?? 0) >= 400) return const [];

    final doc = html_parser.parse(res.data ?? '');
    final rows = <Map<String, Object?>>[];
    for (final cell in doc.querySelectorAll('div[id^="r_"]')) {
      final author = cell.querySelector('strong a[href^="/member/"]');
      final body = cell.querySelector('.reply_content');
      if (author == null || body == null) continue;

      final name = author.text.trim();
      final avatar = cell.querySelector('img.avatar')?.attributes['src'];
      final time = cell.querySelector('.ago')?.attributes['title'];
      rows.add({
        'id': cell.id.replaceFirst('r_', ''),
        'content_rendered': body.innerHtml,
        'member': {
          'username': name,
          'avatar_normal': avatar,
          'url': 'https://www.v2ex.com/member/$name',
        },
        'created': _parsePageTime(time) == null
            ? null
            : _parsePageTime(time)!.millisecondsSinceEpoch ~/ 1000,
      });
    }
    return _buildReplies(rows);
  }

  /// Builds the reply list from raw API rows. Exposed so the quote rules can
  /// be tested against a handmade thread.
  @visibleForTesting
  static List<Reply> parseRepliesForTest(List<Map<String, Object?>> rows) =>
      V2exSource()._buildReplies(rows);

  List<Reply> _buildReplies(List<Map<String, Object?>> rows) {
    final replies = <Reply>[];
    var floor = 0;
    for (final r in rows) {
      final html = (r['content_rendered'] as String?)?.isNotEmpty == true
          ? r['content_rendered'] as String
          : _escape('${r['content'] ?? ''}');
      replies.add(Reply(
        id: '${r['id']}',
        content: html,
        author: r['member'] is Map ? _author(r['member'] as Map) : null,
        createdAt: fromUnixSeconds(r['created']),
        floor: ++floor,
      ));
    }
    return [for (final reply in replies) _withQuote(reply, replies)];
  }

  /// V2EX has no reply threading. Readers write it themselves, opening a reply
  /// with `@someone`, `#12`, or both, so that prefix is lifted out of the body
  /// and shown as a quote instead of being read as part of the sentence.
  static final _mentionPattern = RegExp(
    r'^\s*(?:'
    r'(?:@<a[^>]*href="/member/([^"]+)"[^>]*>[^<]*</a>)'
    r'|(?:@([A-Za-z0-9_]+))'
    r')[\s,，、]*',
  );

  /// A leading `#12`. Only treated as a reference when it names a real,
  /// earlier reply — plenty of posts open with a number that means something
  /// else entirely, and swallowing it would change what the reply says.
  static final _floorPattern = RegExp(r'^\s*#(\d+)[\s,，、]*');

  Reply _withQuote(Reply reply, List<Reply> all) {
    var body = reply.content;
    String? author;
    int? floor;

    // A reply may open with several references, e.g. `@a @b #3`.
    for (var i = 0; i < 4; i++) {
      final mention = _mentionPattern.firstMatch(body);
      if (mention != null) {
        author ??= mention.group(1) ?? mention.group(2);
        body = body.substring(mention.end);
        continue;
      }
      final floorMatch = _floorPattern.firstMatch(body);
      if (floorMatch == null) break;
      final candidate = asInt(floorMatch.group(1));
      if (!_isEarlierFloor(candidate, reply.floor)) break;
      floor ??= candidate;
      body = body.substring(floorMatch.end);
    }
    if (author == null && floor == null) return reply;

    final target =
        _findQuoted(all, author: author, floor: floor, before: reply.floor);
    return Reply(
      id: reply.id,
      content: body.trimLeft(),
      format: reply.format,
      author: reply.author,
      createdAt: reply.createdAt,
      floor: reply.floor,
      likeCount: reply.likeCount,
      quote: ReplyQuote(
        author: author ?? target?.author?.name,
        floor: floor ?? target?.floor,
        excerpt: htmlToPreview(target?.content, max: 90),
      ),
    );
  }

  bool _isEarlierFloor(int? candidate, int? current) =>
      candidate != null && candidate > 0 && current != null && candidate < current;

  /// The reply being answered: by floor when given, otherwise the latest one
  /// from that author that came earlier. Searching the whole thread would
  /// happily return a reply written afterwards.
  Reply? _findQuoted(
    List<Reply> all, {
    String? author,
    int? floor,
    int? before,
  }) {
    if (floor != null) {
      for (final r in all) {
        if (r.floor == floor) return r;
      }
    }
    if (author != null) {
      for (final r in all.reversed) {
        if (r.author?.name != author) continue;
        if (before != null && (r.floor ?? 0) >= before) continue;
        return r;
      }
    }
    return null;
  }

  @override
  String? topicIdFromUrl(Uri uri) {
    if (!uri.host.endsWith('v2ex.com')) return null;
    final m = RegExp(r'^/t/(\d+)').firstMatch(uri.path);
    return m?.group(1);
  }

  List<TopicSummary> _mapList(Object? res) =>
      [for (final t in (res as List).cast<Map>()) _mapTopic(t)];

  TopicSummary _mapTopic(Map t, {String? nodeTitle}) {
    final member = t['member'] as Map?;
    final node = t['node'] as Map?;
    return TopicSummary(
      site: id,
      id: '${t['id']}',
      title: '${t['title']}',
      url: t['url']?.toString() ?? 'https://www.v2ex.com/t/${t['id']}',
      excerpt: htmlToPreview(t['content_rendered']?.toString() ??
          t['content']?.toString()),
      author: member != null
          ? _author(member)
          : (t['last_reply_by'] != null
              ? Author(name: '${t['last_reply_by']}')
              : null),
      sectionLabel: node?['title']?.toString() ?? nodeTitle,
      replyCount: asInt(t['replies']),
      createdAt: fromUnixSeconds(t['created']),
      lastActiveAt: fromUnixSeconds(t['last_touched']),
    );
  }

  Author _author(Map m) => Author(
        name: '${m['username']}',
        avatarUrl: _abs(m['avatar_normal']?.toString() ?? m['avatar_large']?.toString()),
        url: m['url']?.toString(),
        tagline: m['tagline']?.toString(),
      );

  static String? _abs(String? u) {
    if (u == null || u.isEmpty) return null;
    if (u.startsWith('//')) return 'https:$u';
    return u;
  }

  String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('\n', '<br>');

  Future<dynamic> _get(String path,
      {Map<String, String>? query, bool bearer = false}) async {
    Response<dynamic> res;
    try {
      res = await _dio.get<dynamic>(path,
          queryParameters: query,
          options: bearer
              ? Options(headers: {'Authorization': 'Bearer $token'})
              : null);
    } on DioException catch (e) {
      // A 5xx still carries a response and is reported by status below; only
      // a request that never arrived is a reachability problem.
      res = e.response ?? _unreachable(e);
    }
    final code = res.statusCode ?? 0;
    if (code == 401) {
      throw AuthRequiredException(
          id, 'V2EX Token 无效或已过期', AuthRecovery.settings);
    }
    if (code == 403 || code == 429) {
      throw Exception('V2EX 接口限流（HTTP $code），请稍后再试');
    }
    if (code >= 400) throw Exception('V2EX 请求失败（HTTP $code）');
    final data = res.data;
    if (data is String) throw Exception('V2EX 返回了非 JSON 内容');
    if (data is Map && data['success'] == false) {
      throw Exception(data['message']?.toString() ?? 'V2EX 请求失败');
    }
    return data;
  }
}
