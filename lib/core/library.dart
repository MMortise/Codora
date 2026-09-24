import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// A topic kept by the reader: enough to list it and open it again without
/// asking the site, which may be out of reach when they come back for it.
class SavedTopic {
  const SavedTopic({
    required this.site,
    required this.id,
    required this.title,
    required this.url,
    required this.at,
    this.author,
    this.avatarUrl,
  });

  final SiteId site;
  final String id;
  final String title;
  final String url;
  final String? author;
  final String? avatarUrl;

  /// When it was saved, or last read.
  final DateTime at;

  TopicRef get ref => TopicRef(site, id);

  factory SavedTopic.of(TopicDetail d, {DateTime? at}) => SavedTopic(
        site: d.site,
        id: d.id,
        title: d.title,
        url: d.url,
        author: d.author?.name,
        avatarUrl: d.author?.avatarUrl,
        at: at ?? DateTime.now(),
      );

  /// As a card in a list: which forum it is from stands where the board would.
  TopicSummary toSummary() => TopicSummary(
        site: site,
        id: id,
        title: title,
        url: url,
        author: author == null ? null : Author(name: author!, avatarUrl: avatarUrl),
        sectionLabel: site.label,
        lastActiveAt: at,
      );

  Map<String, Object?> toJson() => {
        'site': site.name,
        'id': id,
        'title': title,
        'url': url,
        'author': author,
        'avatar': avatarUrl,
        'at': at.toIso8601String(),
      };

  /// Null for an entry from a site this build does not know, or one that has
  /// been damaged.
  static SavedTopic? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    try {
      final site = SiteId.values.asNameMap()[j['site']];
      if (site == null) return null;
      return SavedTopic(
        site: site,
        id: j['id'] as String,
        title: j['title'] as String,
        url: j['url'] as String,
        author: j['author'] as String?,
        avatarUrl: j['avatar'] as String?,
        at: DateTime.parse(j['at'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// What the reader has bookmarked, and what they have read lately — newest
/// first, both.
class Library {
  const Library({this.bookmarks = const [], this.history = const []});

  static const _bookmarksKey = 'bookmarks';
  static const _historyKey = 'history';

  /// History only has to reach back as far as anyone would look.
  static const historyLimit = 500;

  /// Loaded once before the first frame, like the settings.
  static Library bootstrap = const Library();

  final List<SavedTopic> bookmarks;
  final List<SavedTopic> history;

  bool isBookmarked(TopicRef ref) => bookmarks.any((b) => b.ref == ref);

  /// Adds [topic] to the bookmarks, or takes it out if it is already there.
  Library toggleBookmark(SavedTopic topic) => isBookmarked(topic.ref)
      ? Library(
          bookmarks: [
            for (final b in bookmarks)
              if (b.ref != topic.ref) b,
          ],
          history: history)
      : Library(bookmarks: [topic, ...bookmarks], history: history);

  /// Puts [topic] at the top of the history, once.
  Library withVisit(SavedTopic topic) {
    if (history.isNotEmpty && history.first.ref == topic.ref &&
        history.first.title == topic.title) {
      return this;
    }
    final next = [
      topic,
      for (final h in history)
        if (h.ref != topic.ref) h,
    ];
    if (next.length > historyLimit) next.removeRange(historyLimit, next.length);
    return Library(bookmarks: bookmarks, history: next);
  }

  Library withoutHistory() => Library(bookmarks: bookmarks);

  static List<SavedTopic> _read(List<String>? lines) => [
        for (final line in lines ?? const <String>[])
          ?_decode(line),
      ];

  static SavedTopic? _decode(String line) {
    try {
      return SavedTopic.fromJson(jsonDecode(line));
    } catch (_) {
      return null;
    }
  }

  static Future<Library> load() async {
    final p = await SharedPreferences.getInstance();
    return Library(
      bookmarks: _read(p.getStringList(_bookmarksKey)),
      history: _read(p.getStringList(_historyKey)),
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setStringList(
          _bookmarksKey, [for (final b in bookmarks) jsonEncode(b.toJson())]),
      p.setStringList(
          _historyKey, [for (final h in history) jsonEncode(h.toJson())]),
    ]);
  }
}
