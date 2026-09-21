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

/// The reader themselves on a site: who the stored credentials sign them in
/// as. The rail shows this as a card; a site that cannot answer leaves
/// [ForumSource.member] null and gets no card.
class Member {
  const Member({
    required this.name,
    this.avatarUrl,
    this.url,
    this.tagline,
    this.number,
    this.joinedAt,
    this.badge,
    this.notifications = const [],
    this.unread,
    this.notificationTotal,
    this.notificationsUrl,
    this.note,
    this.stats = const [],
    this.progressUrl,
  });

  final String name;
  final String? avatarUrl;
  final String? url;

  /// The one line forums let people write under their own name.
  final String? tagline;

  /// Signup number, where the site hands one out — V2EX's member id is one.
  final int? number;

  final DateTime? joinedAt;

  /// A short standing the site gives this reader — V2EX's PRO, a Discourse
  /// trust level. Null where the site has nothing to say about it.
  final String? badge;

  /// The newest page of the reader's inbox, newest first.
  final List<Notice> notifications;

  /// How many the site itself says are unread.
  ///
  /// Null for a site that does not track it — V2EX hands back the whole
  /// history either way — and the app then keeps its own mark instead. A real
  /// count is always better than a remembered one, so this wins where it
  /// exists.
  final int? unread;

  /// How many the site is holding altogether, when it says.
  final int? notificationTotal;

  /// Where the whole list lives, for a reader who wants to answer one.
  final Uri? notificationsUrl;

  /// What this card cannot show, and why. Sites use it for the parts of a
  /// profile that a token does not reach.
  final String? note;

  /// The counters a site promotes on, in the order worth reading.
  final List<MemberStat> stats;

  /// Where the site itself explains what is still missing before the next
  /// standing, when the app can only show the counters and not the bar.
  final Uri? progressUrl;

  /// The mark to store once the reader has opened the list — everything up to
  /// here has been put in front of them.
  int get newestNotification =>
      notifications.fold(0, (a, n) => n.id > a ? n.id : a);

  /// How many arrived after [seen].
  ///
  /// Only the newest page is fetched, so this saturates at its length: a
  /// reader back from a fortnight away is told "10+", not the true number.
  /// Only consulted for a site with no [unread] of its own.
  int unreadSince(int seen) => notifications.where((n) => n.id > seen).length;

  /// Whether [unreadSince] has run out of page to count.
  bool saturated(int unread) =>
      notifications.isNotEmpty && unread == notifications.length;
}

/// Where a post stands on likes, from the reader's side.
///
/// A site that says nothing about any of this leaves the flags false, and the
/// post is drawn with its count and nothing to press.
class LikeState {
  const LikeState({
    required this.count,
    this.liked = false,
    this.canLike = false,
    this.canUnlike = false,
  });

  final int count;

  /// Whether this reader is one of them.
  final bool liked;

  /// Whether they may add one. False for their own post, and on a site that
  /// does not let them.
  final bool canLike;

  /// Whether the one they added can still be taken back. Discourse closes
  /// that window a few minutes after the like.
  final bool canUnlike;

  /// Whether pressing it would do anything.
  bool get open => liked ? canUnlike : canLike;
}

/// One number a site counts toward what a reader is allowed to do.
///
/// The value arrives ready to read — hours for a span of time, 2.1k for a
/// count — because what a number means is the source's business and not the
/// card's.
class MemberStat {
  const MemberStat(this.label, this.value, {this.target, this.met = true});

  final String label;
  final String value;

  /// What it has to reach, where the site fixes a number. Null when there is
  /// none, or when only the site can work out what it is.
  final String? target;

  /// False only where there is a [target] and it has not been reached.
  final bool met;
}

/// One line of a site's inbox.
class Notice {
  const Notice({required this.id, required this.text, this.createdAt});

  /// Rises with time on every site that numbers these, which is what makes a
  /// stored id usable as a high-water mark.
  final int id;

  /// Already flattened to one line of plain text.
  final String text;

  final DateTime? createdAt;
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
    this.postId,
    this.liked = false,
    this.canLike = false,
    this.canUnlike = false,
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

  /// The post the topic opens with, where a site numbers it apart from the
  /// topic. Liking is done to a post, not to a thread.
  final String? postId;

  /// As on a [Reply]: whether this reader has liked the opening post, and
  /// what they may do about it.
  final bool liked;
  final bool canLike;
  final bool canUnlike;
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

/// A post a new reply is aimed at, rather than the thread as a whole.
///
/// A forum that threads replies wants the post's own number; the box over
/// which one is written wants a name to show. Both travel together, so the
/// pane hands the same object to either.
class ReplyTarget {
  const ReplyTarget({required this.postId, this.floor, this.author});

  /// The post as the site numbers it.
  final String postId;

  /// Which floor it stands on, where the site counts them. Discourse threads
  /// a reply by this and not by the post id.
  final int? floor;

  /// Who wrote it, for the line over the box.
  final String? author;
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
    this.liked = false,
    this.canLike = false,
    this.canUnlike = false,
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

  /// Whether this reader has liked it, and what they may do about that.
  /// See [LikeState], which is what a site answers with when they do.
  final bool liked;
  final bool canLike;
  final bool canUnlike;

  final List<Reply> children;

  /// The same reply, as it stands after a like or an unlike.
  Reply withLike(LikeState like) => Reply(
        id: id,
        content: content,
        format: format,
        author: author,
        createdAt: createdAt,
        floor: floor,
        likeCount: like.count,
        liked: like.liked,
        canLike: like.canLike,
        canUnlike: like.canUnlike,
        quote: quote,
        children: children,
      );
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

/// Thrown when a site needs something from the reader before it will load —
/// a login, a challenge passed, a credential, or an address to reach it by.
class AuthRequiredException implements Exception {
  AuthRequiredException(this.site, this.message, this.recovery, {this.hint});
  final SiteId site;
  final String message;
  final AuthRecovery recovery;

  /// Replaces the generic line under [message]. A site supplies one when the
  /// fix is not the usual "update your credentials" — a proxy address, say.
  final String? hint;

  @override
  String toString() => message;
}
