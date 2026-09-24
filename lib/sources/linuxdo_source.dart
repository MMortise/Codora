import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;

import '../core/forum_source.dart';
import '../core/http.dart';
import '../core/models.dart';
import '../core/settings.dart';
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

  /// Whether this platform has a browser to read the site through.
  ///
  /// Everything here goes through a WebView, because the challenge's
  /// clearance only works from the browser that earned it — and the WebView
  /// plugin has no Linux implementation. On Linux the site is not slow or
  /// half-working but simply unreachable, and saying so plainly beats a
  /// button into a browser that is not there.
  static bool get supported => defaultTargetPlatform != TargetPlatform.linux;

  static const unsupportedMessage =
      'Linux 版读不了 linux.do：它要靠内置浏览器通过 Cloudflare 验证，'
      '而 Linux 上还没有能用的内置浏览器。';

  /// Signed in, on a platform where that can be used.
  bool get _signedIn => supported && cookieHeaderHas(cookie, kLinuxdoSignIn);

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
  String get accessNote => supported ? _accessNote : unsupportedMessage;

  static const _accessNote = '整站有 Cloudflare 人机验证。用内置浏览器过一次验证，通过后可以直接登录。'
      'passkey 和 Google 登录在内嵌浏览器里用不了（前者要站点授权，后者被 Google 拦），'
      '这种情况在系统浏览器里登录，把 _t 这个 Cookie 复制到下面「手动填写」里。';
  @override
  SiteAccess get access {
    if (!supported) return const SiteAccess(AccessLevel.blocked, '此平台不支持');
    if (!cookieHeaderHas(cookie, 'cf_clearance')) {
      return const SiteAccess(AccessLevel.blocked, '待验证');
    }
    return cookieHeaderHas(cookie, kLinuxdoSignIn)
        ? const SiteAccess(AccessLevel.full, '已登录')
        : const SiteAccess(AccessLevel.limited, '已验证，未登录');
  }

  /// Whether an image has to be fetched through the browser.
  ///
  /// Only the forum's own domain sits behind the challenge. Uploads and emoji
  /// are served from ldstatic.com, which answers any client and sends
  /// `Access-Control-Allow-Origin: *`. Those must go over the normal network:
  /// fetching them from inside the linux.do page makes them cross-origin
  /// requests, which is how they ended up failing before.
  bool needsBrowser(Uri url) => url.host == _origin.host;

  // Images on the forum's own domain are behind the same protection as the
  // API, so they are fetched through the WebView rather than with headers a
  // plain request could send.
  @override
  late final SiteImages images = cookie.isEmpty || !supported
      ? SiteImages.plain
      : SiteImages(
          loader: (url) => needsBrowser(url)
              ? WebViewFetcher.instance
                  .getBytes(_origin, url, userAgent: userAgent)
              : null,
        );

  // Discourse describes the signed-in reader properly, and unlike V2EX it
  // tracks what has been read — so the card's unread count here is the
  // site's own rather than a mark this app keeps.
  @override
  Future<Member> Function()? get member =>
      _signedIn ? _fetchMember : null;

  /// Held to [kMemberDeadline] like every other site. This one needs it
  /// most: the request goes through a WebView that can sit behind an expired
  /// challenge indefinitely, and a card that spins forever says nothing.
  Future<Member> _fetchMember() => _readMember().timeout(
        kMemberDeadline,
        onTimeout: () => throw AuthRequiredException(
          id,
          'linux.do 没有回应',
          AuthRecovery.browser,
          hint: '个人信息 ${kMemberDeadline.inSeconds} 秒没读回来，'
              '多半是人机验证过期了。用内置浏览器重新过一次就好。',
        ),
      );

  Future<Member> _readMember() async {
    // Every read here is asked again because someone pressed 刷新 or an hour
    // went by; a cached answer would defeat both.
    final session = await _get(
      '/session/current.json',
      fresh: true,
      // Discourse answers this one with a 404 when nobody is signed in. Read
      // as a missing page that says nothing; what it means is that the
      // browser's sign-in has gone — expired, or rotated out from under the
      // copy in settings, which is why a card was offered at all.
      notFound: () => AuthRequiredException(
        id,
        'linux.do 的登录已经失效',
        AuthRecovery.browser,
        hint: '站点说这边没有登录。到设置里先退出登录，再用内置浏览器登录一次。',
      ),
    );
    final me = session['current_user'] as Map? ?? const {};
    final username = '${me['username']}';

    // The other two only add to what is already in hand. A card missing a
    // join date is worth more than no card, so neither can sink the whole
    // thing — a Discourse instance is free to lock either one down.
    Map? profile;
    List? notices;
    Map? summary;
    await (
      Future(() async {
        try {
          profile = (await _get('/u/$username.json', fresh: true))['user']
              as Map?;
        } catch (_) {}
      }),
      Future(() async {
        try {
          notices = (await _get('/notifications.json',
                  query: {'filter': 'unread', 'limit': '5'},
                  fresh: true))['notifications']
              as List?;
        } catch (_) {}
      }),
      Future(() async {
        try {
          summary =
              (await _get('/u/$username/summary.json', fresh: true))
                  ['user_summary'] as Map?;
        } catch (_) {}
      }),
    ).wait;

    return parseMember(me,
        profile: profile, notices: notices, summary: summary);
  }

  /// Built apart from the requests so the shapes can be checked without one.
  @visibleForTesting
  static Member parseMember(Map me,
      {Map? profile, List? notices, Map? summary}) {
    final username = '${me['username']}';
    final rows = (notices ?? const []).cast<Map>();
    return Member(
      name: username,
      avatarUrl: _avatarOf(me['avatar_template']?.toString(), size: 144),
      url: '$_origin/u/$username',
      // Discourse separates the handle from the display name, and keeps a
      // short bio besides. Either is more use under a name than nothing.
      tagline: _text(htmlToPreview(profile?['bio_excerpt']?.toString())) ??
          _text(me['name']?.toString()),
      number: asInt(me['id']),
      joinedAt: fromIso(profile?['created_at']),
      badge: _standing(me),
      // Counted by the forum itself, so there is no mark to keep and no
      // saturating at whatever one page happens to hold.
      //
      // `all_unread_notifications_count` is the one Discourse puts on its own
      // bell. `unread_notifications` sounds like the number but is only the
      // part of it that is not high priority — it read 0 here while two
      // replies were waiting.
      unread: asInt(me['all_unread_notifications_count']) ??
          asInt(me['unread_notifications']),
      notifications: [
        for (final row in rows)
          if (asInt(row['id']) case final id?)
            Notice(
              id: id,
              text: _noticeText(row),
              createdAt: fromIso(row['created_at']),
            ),
      ],
      notificationsUrl: Uri.parse('$_origin/u/$username/notifications'),
      stats: _progress(me, summary),
      // Where the rest of it is. The counters below are the right ones, but
      // the bar for level 3 moves with the site and is only worked out on
      // its side.
      progressUrl: summary == null ? null : _connect,
      note: _levelNote(me, summary),
    );
  }

  /// linux.do's own page for what is still missing before the next level. It
  /// signs in separately and reads the site from the inside, which is how it
  /// can show the hundred-day windows this app cannot.
  static final _connect = Uri.parse('https://connect.linux.do/');

  /// What Discourse asks for before the next level, where the number is fixed
  /// and counted over the whole of a reader's time.
  ///
  /// Level 3 is deliberately absent: every one of its requirements is
  /// measured over the last hundred days, and two of them against how busy
  /// the site itself has been — a quarter of the topics it saw, a quarter of
  /// the posts. Nothing a member can read says either of those, so guessing a
  /// bar here would be worse than showing none. These are also Discourse's
  /// own defaults; a site may have raised them, and nothing public says.
  static const _wanted = <int, Map<String, int>>{
    1: {'topics_entered': 5, 'posts_read_count': 30, 'time_read': 600},
    2: {
      'days_visited': 15,
      'topics_entered': 20,
      'posts_read_count': 100,
      'time_read': 3600,
      'likes_given': 1,
      'likes_received': 1,
    },
  };

  /// The counters a level is decided on, ready to read.
  static List<MemberStat> _progress(Map me, Map? summary) {
    if (summary == null) return const [];
    final wants = _wanted[(asInt(me['trust_level']) ?? 0) + 1] ?? const {};

    MemberStat? counter(String label, String key, {bool isTime = false}) {
      final now = asInt(summary[key]);
      if (now == null) return null;
      String say(int n) => isTime ? _spell(n) : compactCount(n);
      final want = wants[key];
      return MemberStat(
        label,
        say(now),
        target: want == null ? null : say(want),
        met: want == null || now >= want,
      );
    }

    return [
      for (final counted in [
        counter('访问天数', 'days_visited'),
        counter('浏览话题', 'topics_entered'),
        counter('已读帖子', 'posts_read_count'),
        counter('阅读时长', 'time_read', isTime: true),
        counter('送出的赞', 'likes_given'),
        counter('收到的赞', 'likes_received'),
      ])
        ?counted,
    ];
  }

  /// Said once, under the counters, where a bar cannot be drawn for them.
  static String? _levelNote(Map me, Map? summary) {
    if (summary == null) return null;
    final level = asInt(me['trust_level']) ?? 0;
    return level >= 2
        ? '这些是总计。3 级的门槛看最近 100 天，还跟全站活跃度挂钩，只有站点自己算得出'
        : null;
  }

  /// A span of time as someone would say it.
  static String _spell(int seconds) {
    if (seconds < 3600) return '${(seconds / 60).round()} 分钟';
    final hours = seconds / 3600;
    return hours < 10
        ? '${hours.toStringAsFixed(1)} 小时'
        : '${hours.round()} 小时';
  }

  /// What the forum says this reader counts as. Staff first — it outranks a
  /// trust level and is the thing anyone would want to see.
  static String? _standing(Map me) {
    if (me['admin'] == true) return 'ADMIN';
    if (me['moderator'] == true) return 'MOD';
    final level = asInt(me['trust_level']);
    return level == null ? null : 'LV$level';
  }

  /// One line for a notification: who, and what it was about.
  static String _noticeText(Map row) {
    final data = row['data'] as Map? ?? const {};
    final who = _text(data['display_username']?.toString());
    final what = _text(row['fancy_title']?.toString()) ??
        _text(data['topic_title']?.toString()) ??
        _text(data['badge_name']?.toString());
    return [?who, ?what].join(' · ');
  }

  static String? _text(String? v) {
    final s = v?.trim() ?? '';
    return s.isEmpty ? null : s;
  }

  /// Discourse hands back a template with the size left out. One helper for
  /// every size the app asks for, so a change in how avatars are served is
  /// made once rather than in each place that wants a different one.
  static String? _avatarOf(String? template, {int size = 96}) {
    if (template == null || template.isEmpty) return null;
    final sized = template.replaceAll('{size}', '$size');
    return sized.startsWith('http') ? sized : '$_origin$sized';
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
    final opening = parseLike(first);
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
      // The topic's own like count is the sum over every post in it; what a
      // reader can act on is the opening post, so its own stands here.
      likeCount: opening.count,
      createdAt: fromIso(res['created_at']),
      postId: asInt(first['id'])?.toString(),
      liked: opening.liked,
      canLike: opening.canLike,
      canUnlike: opening.canUnlike,
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

  // Discourse is a forum the app can actually answer, and the browser the
  // feed runs in is already signed in to it. Anonymous readers get no box:
  // there is nothing to send with.
  @override
  SendReply? get reply =>
      _signedIn ? _reply : null;

  // Discourse counts a like as an action on a post, and taking one back as
  // the removal of that action. Both go out over the session the reading
  // already uses.
  @override
  ActOnLike? get like =>
      _signedIn ? _like : null;

  // Discourse takes a picture before the post that shows it exists: its own
  // composer hands the file over, is told a short address for it, and writes
  // that into the body. Nothing here departs from that.
  @override
  UploadImage? get uploadImage =>
      _signedIn ? _uploadImage : null;

  Future<LikeState> _like(String postId, {required bool like}) async {
    _requireCookie();
    final id = asInt(postId) ?? postId;
    final answer = like
        ? await _write('POST', '/post_actions',
            body: {'id': id, 'post_action_type_id': _likeAction})
        : await _write(
            'DELETE', '/post_actions/$id?post_action_type_id=$_likeAction');
    return parseLike(answer);
  }

  /// Discourse numbers what can be done to a post; 2 is the like.
  static const _likeAction = 2;

  /// Where a post stands on likes, out of the summary every post carries.
  ///
  /// No line at all means the site said nothing, and nothing is then offered:
  /// Discourse leaves the line out when the count is zero *and* this reader
  /// may not act — their own post. Where they may, it says so, which is also
  /// what comes back after the last like is taken away.
  @visibleForTesting
  static LikeState parseLike(Map post) {
    for (final action
        in (post['actions_summary'] as List? ?? const []).cast<Map>()) {
      if (asInt(action['id']) != _likeAction) continue;
      return LikeState(
        count: asInt(action['count']) ?? 0,
        liked: action['acted'] == true,
        canLike: action['can_act'] == true,
        canUnlike: action['can_undo'] == true,
      );
    }
    return const LikeState(count: 0);
  }

  Future<Reply> _reply(String topicId, String text, {ReplyTarget? to}) async {
    _requireCookie();
    final answer = await _write('POST', '/posts', body: {
      'raw': text,
      'topic_id': asInt(topicId) ?? topicId,
      // Discourse threads a reply by the floor it answers rather than by the
      // post's id, and left out altogether it answers the thread as a whole.
      'reply_to_post_number': ?to?.floor,
    });
    // Discourse answers with the post it made; some installs wrap it.
    final post = answer['post'] as Map? ?? answer;
    if (asInt(post['id']) == null) {
      // It may well have gone out — saying nothing, or drawing an empty
      // reply where theirs should be, would be worse than saying to look.
      throw Exception('回复可能已经发出去了，但没读懂 linux.do 的回应，刷新一下看看');
    }
    return parsePost(post);
  }

  /// How big a picture can be before it is not worth the attempt.
  ///
  /// Not the forum's limit — that is the forum's to state, in its own words,
  /// and it will. This is the bridge's: the bytes cross into the page as
  /// base64, a third longer again, over a channel meant for small messages.
  /// Past here, saying so at once beats a minute of nothing.
  static const _pictureLimit = 12 * 1024 * 1024;

  Future<String> _uploadImage(String filename, Uint8List bytes) async {
    _requireCookie();
    if (bytes.length > _pictureLimit) {
      final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      throw Exception('这张图 $mb MB，太大了，先压一下再传');
    }
    final answer = await _writeFile(
      '/uploads.json',
      filename: filename,
      bytes: bytes,
      fields: {
        // What the picture is for, which is what decides where the forum
        // keeps it. Discourse reads `type`; an install old enough to want
        // `upload_type` finds that, and neither minds the other being there.
        'type': 'composer',
        'upload_type': 'composer',
      },
    );
    return uploadMarkdown(answer, filename: filename);
  }

  /// What to write into the box for a picture linux.do is now holding.
  ///
  /// The `upload://` address is the one to use rather than the plain URL: the
  /// forum resolves it as it renders the post, so the picture keeps showing
  /// when the file behind it moves to another store. The size goes in because
  /// Discourse draws a picture at the size the markdown names, and a phone
  /// screenshot with no size named is drawn at all 1179 of its pixels.
  @visibleForTesting
  static String uploadMarkdown(Map upload, {required String filename}) {
    final at = _text(upload['short_url']?.toString()) ??
        _text(upload['url']?.toString());
    if (at == null) {
      throw Exception('图片传上去了，但 linux.do 没说它在哪儿，刷新一下看看');
    }
    final name = _text(upload['original_filename']?.toString()) ?? filename;
    final width = asInt(upload['width']);
    final height = asInt(upload['height']);
    final drawn = width != null && height != null && width > 0 && height > 0;
    final size = drawn ? '|${width}x$height' : '';
    // The name sits inside the brackets, where these three characters mean
    // something else. A screenshot called `a[1]|b.png` would otherwise end
    // the link early and leave the address as text.
    final plain = name.replaceAll(RegExp(r'[\[\]|]'), '_');
    return '![$plain$size]($at)';
  }

  /// Sends something to linux.do, rather than asking it for something.
  Future<Map> _write(String method, String path,
      {Map<String, Object?>? body}) async {
    final csrf = await _csrf();
    try {
      final answer = await WebViewFetcher.instance.sendJson(
        _origin,
        path,
        method: method,
        body: body,
        headers: {'X-CSRF-Token': csrf},
        userAgent: userAgent,
      );
      if (answer is! Map) throw Exception('linux.do 返回了意外的结果');
      return answer;
    } on WebViewFetchException catch (e) {
      throw Exception(postProblem(e));
    }
  }

  /// The same, for a file. It cannot share [_write]'s body: a picture goes as
  /// a form rather than as JSON, and it is the browser that has to write that
  /// form.
  Future<Map> _writeFile(
    String path, {
    required String filename,
    required Uint8List bytes,
    Map<String, String> fields = const {},
  }) async {
    final csrf = await _csrf();
    try {
      final answer = await WebViewFetcher.instance.sendFile(
        _origin,
        path,
        field: 'file',
        filename: filename,
        bytes: bytes,
        contentType: pictureContentType(filename),
        fields: fields,
        headers: {'X-CSRF-Token': csrf},
        userAgent: userAgent,
      );
      if (answer is! Map) throw Exception('linux.do 返回了意外的结果');
      return answer;
    } on WebViewFetchException catch (e) {
      throw Exception(uploadProblem(e));
    }
  }

  /// The token Rails will not take a write without.
  ///
  /// Read per write rather than kept: it belongs to the session cookie, and
  /// that can be replaced under the app at any point by a sign-in in the
  /// visible browser.
  Future<String> _csrf() async {
    final csrf = '${(await _get('/session/csrf.json'))['csrf'] ?? ''}';
    if (csrf.isEmpty) {
      throw Exception('linux.do 没有给出提交凭证，重新登录一次再试');
    }
    return csrf;
  }

  /// What to show when the forum refuses something.
  ///
  /// Discourse explains itself in the body — the post is too short, you are
  /// posting too fast, the topic is closed — and that sentence is the only
  /// part worth putting in front of anyone. A status code on its own says
  /// nothing about what to do differently.
  @visibleForTesting
  static String postProblem(WebViewFetchException e) {
    if (_said(e) case final sentence?) return sentence;
    if (e.isChallenge) return '人机验证过期了，用内置浏览器重新过一次';
    if (e.status == 404) return '这个帖子不在了';
    if (e.status == 0) return '没能把回复送出去，检查一下网络';
    return '没能发送（HTTP ${e.status}）';
  }

  /// The same for a picture. Discourse is usually the one talking here as
  /// well — too big, not that kind of file, too many today — and only the
  /// fallbacks differ, because a refused upload does not mean the thread is
  /// gone.
  @visibleForTesting
  static String uploadProblem(WebViewFetchException e) {
    if (_said(e) case final sentence?) return sentence;
    // A 403 is not among these: the forum explains a refusal of its own in
    // the body, which [_said] has already read, and a 403 with nothing in it
    // is Cloudflare's — which is what [WebViewFetchException.isChallenge]
    // above has just said.
    if (e.isChallenge) return '人机验证过期了，用内置浏览器重新过一次';
    if (e.status == 413) return '图片太大了，linux.do 没有收';
    if (e.status == 422) return 'linux.do 不接受这张图片';
    if (e.status == 0) return '没能把图片传上去，检查一下网络';
    return '没能上传（HTTP ${e.status}）';
  }

  /// Whatever the forum itself said about the refusal, or null when it said
  /// nothing a reader could act on.
  static String? _said(WebViewFetchException e) {
    try {
      final data = jsonDecode(e.body);
      if (data is Map) {
        final said = [
          for (final line in (data['errors'] as List? ?? const []))
            if ('$line'.trim().isNotEmpty) '$line'.trim(),
        ];
        if (said.isNotEmpty) return said.join('；');
        final one = '${data['error'] ?? data['message'] ?? ''}'.trim();
        if (one.isNotEmpty) return one;
      }
    } catch (_) {
      // Not JSON. The status is then all there is to go on.
    }
    return null;
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

  /// Built apart from the request, so what the forum makes of a reply can be
  /// checked without sending one.
  @visibleForTesting
  static Reply parsePost(Map post) => _mapPost(post);

  static Reply _mapPost(Map p) {
    final like = parseLike(p);
    final cooked = '${p['cooked'] ?? ''}';
    return Reply(
      id: '${p['id']}',
      content: cooked,
      author: _postAuthor(p),
      createdAt: fromIso(p['created_at']),
      floor: asInt(p['post_number']),
      likeCount: like.count,
      liked: like.liked,
      canLike: like.canLike,
      canUnlike: like.canUnlike,
      quote: _answered(p, cooked),
    );
  }

  /// Which post a reply was written to, where Discourse says.
  ///
  /// Only when the body does not carry it already: someone who pressed quote
  /// rather than reply gets an `<aside class="quote">` inside the post, with
  /// the name and the words in it, and a line above saying the same thing
  /// would be the second copy of one thought.
  static ReplyQuote? _answered(Map p, String cooked) {
    final floor = asInt(p['reply_to_post_number']);
    if (floor == null) return null;
    if (cooked.contains('<aside class="quote')) return null;
    return ReplyQuote(
      author: _text((p['reply_to_user'] as Map?)?['username']?.toString()),
      floor: floor,
    );
  }

  static Author _author(Map u) => Author(
        name: '${u['username']}',
        avatarUrl: _avatarOf(u['avatar_template']?.toString()),
        url: 'https://linux.do/u/${u['username']}',
        tagline: u['name']?.toString(),
      );

  static Author? _postAuthor(Map p) =>
      p['username'] == null ? null : _author(p);

  void _requireCookie() {
    _requireSupported();
    if (!cookieHeaderHas(cookie, 'cf_clearance')) {
      throw AuthRequiredException(
          id, '需要先完成 linux.do 的人机验证', AuthRecovery.browser);
    }
  }

  void _requireSupported() {
    if (!supported) throw Exception(unsupportedMessage);
  }

  /// [fresh] for a read whose whole point is that it is current — what the
  /// inbox holds *now*. `no-store` already keeps the browser's own cache out
  /// of it; an address nobody has asked for before is what also keeps out the
  /// ones in between, which this site has several of.
  /// [notFound] for a read where a 404 means something of its own — the
  /// session endpoint answers with one when there is nobody signed in, and
  /// "this page does not exist" is not what a reader needs to hear about it.
  Future<Map> _get(String path,
      {Map<String, String>? query,
      bool fresh = false,
      Exception Function()? notFound}) async {
    final params = {
      ...?query,
      if (fresh) '_': '${DateTime.now().millisecondsSinceEpoch}',
    };
    final target = params.isEmpty
        ? path
        : Uri.parse(path).replace(
            queryParameters: {
              ...Uri.parse(path).queryParameters,
              ...params,
            },
          ).toString();

    _requireSupported();
    final Object? data;
    try {
      data = await WebViewFetcher.instance
          .getJson(_origin, target, userAgent: userAgent);
    } on WebViewFetchException catch (e) {
      if (e.isChallenge) {
        throw AuthRequiredException(
            id, 'linux.do 的人机验证已过期', AuthRecovery.browser);
      }
      if (e.status == 404) {
        throw notFound?.call() ?? Exception('这个内容不存在，或者没有权限看');
      }
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
