import 'models.dart';

/// Topics the reader never wants to see: from a board, by an author, or with
/// a word in the title.
///
/// Boards and authors belong to a site — a name on V2EX is nobody in
/// particular on linux.do — so they are kept per site. Words are not: a
/// reader tired of a subject is tired of it everywhere.
class BlockList {
  const BlockList({
    this.keywords = const {},
    this.authors = const {},
    this.sections = const {},
  });

  static const empty = BlockList();

  /// Matched against titles, ignoring case.
  final Set<String> keywords;

  /// `site:name` — see [entry].
  final Set<String> authors;

  /// `site:board`, the board as the list labels it.
  final Set<String> sections;

  static String entry(SiteId site, String name) => '${site.name}:$name';

  /// The site and name of a stored entry, or null for one from a site this
  /// build does not know.
  static (SiteId, String)? parse(String entry) {
    final at = entry.indexOf(':');
    if (at <= 0) return null;
    final site = SiteId.values.asNameMap()[entry.substring(0, at)];
    return site == null ? null : (site, entry.substring(at + 1));
  }

  bool get isEmpty => keywords.isEmpty && authors.isEmpty && sections.isEmpty;

  /// Which rule [topic] falls under, or null for one the reader wants.
  String? reasonFor(TopicSummary topic) {
    if (topic.author case final author?
        when authors.contains(entry(topic.site, author.name))) {
      return '作者 ${author.name}';
    }
    if (topic.sectionLabel case final board?
        when sections.contains(entry(topic.site, board))) {
      return '节点 $board';
    }
    final title = topic.title.toLowerCase();
    for (final word in keywords) {
      if (title.contains(word.toLowerCase())) return '关键词 $word';
    }
    return null;
  }

  bool blocks(TopicSummary topic) => reasonFor(topic) != null;

  BlockList withKeyword(String word, {bool blocked = true}) {
    final w = word.trim();
    if (w.isEmpty) return this;
    return _copy(keywords: _toggle(keywords, w, blocked));
  }

  BlockList withAuthor(SiteId site, String name, {bool blocked = true}) =>
      _copy(authors: _toggle(authors, entry(site, name), blocked));

  BlockList withSection(SiteId site, String board, {bool blocked = true}) =>
      _copy(sections: _toggle(sections, entry(site, board), blocked));

  static Set<String> _toggle(Set<String> set, String value, bool on) =>
      on ? {...set, value} : {for (final v in set) if (v != value) v};

  BlockList _copy(
          {Set<String>? keywords,
          Set<String>? authors,
          Set<String>? sections}) =>
      BlockList(
        keywords: keywords ?? this.keywords,
        authors: authors ?? this.authors,
        sections: sections ?? this.sections,
      );

  @override
  bool operator ==(Object other) =>
      other is BlockList &&
      _same(other.keywords, keywords) &&
      _same(other.authors, authors) &&
      _same(other.sections, sections);

  static bool _same(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  int get hashCode => Object.hash(
      Object.hashAllUnordered(keywords),
      Object.hashAllUnordered(authors),
      Object.hashAllUnordered(sections));
}
