enum SiteId { v2ex, linuxdo, juejin }

extension SiteIdX on SiteId {
  String get label => switch (this) {
        SiteId.v2ex => 'V2EX',
        SiteId.linuxdo => 'Linux.do',
        SiteId.juejin => '掘金',
      };
}

class Section {
  const Section({
    required this.id,
    required this.title,
    this.subtitle,
    this.group,
  });
  final String id;
  final String title;

  /// Latin slug shown under the title in the section blocks (e.g. 程序员 /
  /// programmer). All three sites give us one, so it doubles as a hint for
  /// readers who know a board by its URL.
  final String? subtitle;
  final String? group;
}

class Author {
  const Author({required this.name, this.avatarUrl, this.url, this.tagline});
  final String name;
  final String? avatarUrl;
  final String? url;
  final String? tagline;
}

class TopicSummary {
  const TopicSummary({
    required this.site,
    required this.id,
    required this.title,
    required this.url,
    this.excerpt,
    this.author,
    this.sectionLabel,
    this.replyCount,
    this.viewCount,
    this.likeCount,
    this.createdAt,
    this.lastActiveAt,
    this.coverUrl,
  });
  final SiteId site;
  final String id;
  final String title;
  final String url;
  final String? excerpt;
  final Author? author;
  final String? sectionLabel;
  final int? replyCount;
  final int? viewCount;
  final int? likeCount;
  final DateTime? createdAt;
  final DateTime? lastActiveAt;
  final String? coverUrl;
}

/// How a site hands over post bodies. The renderer is picked from this, so a
/// source states its format instead of converting to someone else's.
enum BodyFormat { html, markdown }

class TopicDetail {
  const TopicDetail({
    required this.site,
    required this.id,
    required this.title,
    required this.url,
    required this.content,
    this.format = BodyFormat.html,
    this.author,
    this.sectionLabel,
    this.replyCount,
    this.viewCount,
    this.likeCount,
    this.createdAt,
  });
  final SiteId site;
  final String id;
  final String title;
  final String url;
  final String content;
  final BodyFormat format;
  final Author? author;
  final String? sectionLabel;
  final int? replyCount;
  final int? viewCount;
  final int? likeCount;
  final DateTime? createdAt;
}

/// Who a reply is answering.
///
/// Some forums model this; V2EX does not, but its readers write it by hand as
/// `@someone` and `#12`, so a source can recover it from the text.
class ReplyQuote {
  const ReplyQuote({this.author, this.floor, this.excerpt});

  final String? author;
  final int? floor;

  /// One line of what is being answered, when the source can find it.
  final String? excerpt;

  bool get isEmpty => author == null && floor == null;
}

class Reply {
  const Reply({
    required this.id,
    required this.content,
    this.format = BodyFormat.html,
    this.author,
    this.createdAt,
    this.floor,
    this.likeCount,
    this.quote,
    this.children = const [],
  });
  final String id;
  final String content;
  final BodyFormat format;

  /// Set when this reply answers an earlier one.
  final ReplyQuote? quote;
  final Author? author;
  final DateTime? createdAt;
  final int? floor;
  final int? likeCount;
  final List<Reply> children;
}

class PageResult<T> {
  const PageResult({required this.items, this.nextCursor, this.total});
  final List<T> items;
  final String? nextCursor;
  final int? total;
  bool get hasMore => nextCursor != null;
}

class TopicRef {
  const TopicRef(this.site, this.id);
  final SiteId site;
  final String id;
  @override
  bool operator ==(Object other) =>
      other is TopicRef && other.site == site && other.id == id;
  @override
  int get hashCode => Object.hash(site, id);
}

class FeedKey {
  const FeedKey(this.site, this.sectionId);
  final SiteId site;
  final String sectionId;
  @override
  bool operator ==(Object other) =>
      other is FeedKey && other.site == site && other.sectionId == sectionId;
  @override
  int get hashCode => Object.hash(site, sectionId);
}

/// How much of a site the current credentials reach. Every source reports
/// this the same way, so the rail, the settings page and the error view can
/// render site state without knowing which site they are looking at.
enum AccessLevel {
  /// Readable without any setup.
  open,

  /// Signed in; may see more than an anonymous visitor.
  full,

  /// Usable but degraded (e.g. challenge passed but not signed in).
  limited,

  /// Nothing loads until the user does something.
  blocked,
}

class SiteAccess {
  const SiteAccess(this.level, this.label);
  final AccessLevel level;

  /// Short human phrase: 匿名浏览 / 已登录 / 待验证.
  final String label;
}

/// What the user has to do to get past an [AuthRequiredException].
enum AuthRecovery {
  /// Open the in-app browser for this site (Cloudflare challenge, login).
  browser,

  /// Go to the settings page and fill in a credential.
  settings,
}

/// Thrown when a site needs the user to (re)authenticate or pass a challenge.
class AuthRequiredException implements Exception {
  AuthRequiredException(this.site, this.message, this.recovery);
  final SiteId site;
  final String message;
  final AuthRecovery recovery;
  @override
  String toString() => message;
}
