import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'disk_cache.dart';
import 'models.dart';

/// Lists and threads kept on disk, so the app has something to show before
/// the network answers — or when it does not answer at all.
///
/// Every copy is filed under the site, what it is, and who was reading: a
/// fingerprint of the credential that fetched it. Recommendations follow the
/// account, and a signed-in reader sees boards an anonymous one does not, so
/// a copy made for one reader must never stand in for another's. A copy
/// nobody can ask for any more simply ages out of the cache.
///
/// Written with a version, and read back only at that version: a copy from a
/// build that shaped things differently is treated as no copy at all.
class Snapshots {
  Snapshots({required this.read, required this.write});

  Snapshots.on(DiskCache cache) : this(read: cache.read, write: cache.write);

  /// The one the app uses. Replaced in tests.
  static Snapshots instance = Snapshots.on(DiskCache.pages);

  final Future<Uint8List?> Function(Uri key) read;
  final Future<void> Function(Uri key, Uint8List bytes) write;

  static const _version = 1;

  /// A short, stable stand-in for a credential. Nothing about the credential
  /// can be read back from it.
  static String fingerprint(String credential) => credential.isEmpty
      ? 'anon'
      : sha1.convert(utf8.encode(credential)).toString().substring(0, 12);

  static Uri _key(String kind, SiteId site, String account, String id) =>
      Uri(scheme: 'codora', host: kind, pathSegments: [site.name, account, id]);

  Future<Map<String, dynamic>?> _read(Uri key) async {
    final bytes = await read(key);
    if (bytes == null) return null;
    try {
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic> || data['v'] != _version) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(Uri key, Map<String, dynamic> body) => write(
      key,
      Uint8List.fromList(utf8.encode(jsonEncode({
        'v': _version,
        'savedAt': DateTime.now().toIso8601String(),
        ...body,
      }))));

  // ---------- a feed's first page ----------

  Future<void> saveFeed(FeedKey key, String account, PageResult<TopicSummary> page) =>
      _write(_key('feed', key.site, account, key.sectionId), {
        'items': [for (final t in page.items) summaryToJson(t)],
        'next': page.nextCursor,
      });

  Future<SavedPage<TopicSummary>?> loadFeed(FeedKey key, String account) async {
    final data = await _read(_key('feed', key.site, account, key.sectionId));
    if (data == null) return null;
    try {
      return SavedPage(
        items: [
          for (final t in data['items'] as List)
            summaryFromJson(t as Map<String, dynamic>),
        ],
        nextCursor: data['next'] as String?,
        savedAt: DateTime.parse(data['savedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  // ---------- a thread ----------

  Future<void> saveTopic(TopicDetail d, String account) =>
      _write(_key('topic', d.site, account, d.id), {'topic': detailToJson(d)});

  Future<TopicDetail?> loadTopic(TopicRef r, String account) async {
    final data = await _read(_key('topic', r.site, account, r.id));
    if (data == null) return null;
    try {
      return detailFromJson(data['topic'] as Map<String, dynamic>,
          savedAt: DateTime.parse(data['savedAt'] as String));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveReplies(TopicRef r, String account, PageResult<Reply> page) =>
      _write(_key('replies', r.site, account, r.id), {
        'items': [for (final x in page.items) replyToJson(x)],
        'next': page.nextCursor,
        'total': page.total,
      });

  Future<SavedPage<Reply>?> loadReplies(TopicRef r, String account) async {
    final data = await _read(_key('replies', r.site, account, r.id));
    if (data == null) return null;
    try {
      return SavedPage(
        items: [
          for (final x in data['items'] as List)
            replyFromJson(x as Map<String, dynamic>),
        ],
        nextCursor: data['next'] as String?,
        total: data['total'] as int?,
        savedAt: DateTime.parse(data['savedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// A page read back from disk, and when it was written there.
class SavedPage<T> {
  const SavedPage({
    required this.items,
    required this.savedAt,
    this.nextCursor,
    this.total,
  });
  final List<T> items;
  final String? nextCursor;
  final int? total;
  final DateTime savedAt;
}

// ---------- the models, as JSON ----------

String? _time(DateTime? t) => t?.toIso8601String();
DateTime? _parseTime(Object? s) => s is String ? DateTime.tryParse(s) : null;

Map<String, dynamic>? authorToJson(Author? a) => a == null
    ? null
    : {'name': a.name, 'avatar': a.avatarUrl, 'url': a.url, 'tagline': a.tagline};

Author? authorFromJson(Object? j) => j is Map<String, dynamic>
    ? Author(
        name: j['name'] as String,
        avatarUrl: j['avatar'] as String?,
        url: j['url'] as String?,
        tagline: j['tagline'] as String?,
      )
    : null;

Map<String, dynamic> summaryToJson(TopicSummary t) => {
      'site': t.site.name,
      'id': t.id,
      'title': t.title,
      'url': t.url,
      'excerpt': t.excerpt,
      'author': authorToJson(t.author),
      'section': t.sectionLabel,
      'replies': t.replyCount,
      'views': t.viewCount,
      'likes': t.likeCount,
      'created': _time(t.createdAt),
      'active': _time(t.lastActiveAt),
      'cover': t.coverUrl,
    };

TopicSummary summaryFromJson(Map<String, dynamic> j) => TopicSummary(
      site: SiteId.values.byName(j['site'] as String),
      id: j['id'] as String,
      title: j['title'] as String,
      url: j['url'] as String,
      excerpt: j['excerpt'] as String?,
      author: authorFromJson(j['author']),
      sectionLabel: j['section'] as String?,
      replyCount: j['replies'] as int?,
      viewCount: j['views'] as int?,
      likeCount: j['likes'] as int?,
      createdAt: _parseTime(j['created']),
      lastActiveAt: _parseTime(j['active']),
      coverUrl: j['cover'] as String?,
    );

Map<String, dynamic> detailToJson(TopicDetail d) => {
      'site': d.site.name,
      'id': d.id,
      'title': d.title,
      'url': d.url,
      'content': d.content,
      'format': d.format.name,
      'author': authorToJson(d.author),
      'section': d.sectionLabel,
      'replies': d.replyCount,
      'views': d.viewCount,
      'likes': d.likeCount,
      'created': _time(d.createdAt),
      'postId': d.postId,
      'liked': d.liked,
      'canLike': d.canLike,
      'canUnlike': d.canUnlike,
    };

TopicDetail detailFromJson(Map<String, dynamic> j, {DateTime? savedAt}) =>
    TopicDetail(
      site: SiteId.values.byName(j['site'] as String),
      id: j['id'] as String,
      title: j['title'] as String,
      url: j['url'] as String,
      content: j['content'] as String,
      format: BodyFormat.values.byName(j['format'] as String),
      author: authorFromJson(j['author']),
      sectionLabel: j['section'] as String?,
      replyCount: j['replies'] as int?,
      viewCount: j['views'] as int?,
      likeCount: j['likes'] as int?,
      createdAt: _parseTime(j['created']),
      postId: j['postId'] as String?,
      // What the reader may do to a post is the site's answer at the time; a
      // copy read offline offers nothing to press.
      liked: j['liked'] as bool? ?? false,
      savedAt: savedAt,
    );

Map<String, dynamic> replyToJson(Reply r) => {
      'id': r.id,
      'content': r.content,
      'format': r.format.name,
      'author': authorToJson(r.author),
      'created': _time(r.createdAt),
      'floor': r.floor,
      'likes': r.likeCount,
      'liked': r.liked,
      'quote': r.quote == null
          ? null
          : {
              'author': r.quote!.author,
              'floor': r.quote!.floor,
              'excerpt': r.quote!.excerpt,
            },
      'children': [for (final c in r.children) replyToJson(c)],
    };

Reply replyFromJson(Map<String, dynamic> j) {
  final quote = j['quote'];
  return Reply(
    id: j['id'] as String,
    content: j['content'] as String,
    format: BodyFormat.values.byName(j['format'] as String),
    author: authorFromJson(j['author']),
    createdAt: _parseTime(j['created']),
    floor: j['floor'] as int?,
    likeCount: j['likes'] as int?,
    liked: j['liked'] as bool? ?? false,
    quote: quote is Map<String, dynamic>
        ? ReplyQuote(
            author: quote['author'] as String?,
            floor: quote['floor'] as int?,
            excerpt: quote['excerpt'] as String?,
          )
        : null,
    children: [
      for (final c in j['children'] as List? ?? const [])
        replyFromJson(c as Map<String, dynamic>),
    ],
  );
}
