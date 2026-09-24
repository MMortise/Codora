import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// How far into a topic the reader has got.
class ReadProgress {
  const ReadProgress({this.replies, this.position});

  /// How many replies the topic had the last time it was read. Null for a
  /// topic read before this was kept, which is never announced as having new
  /// ones: there is nothing to count them from.
  final int? replies;

  /// Which reply, counted from zero in the thread's own order, was on screen
  /// when the reader last left it. Null while they never got past the post.
  final int? position;

  /// How many replies arrived since, given the topic has [current] now.
  int newSince(int? current) {
    final seen = replies;
    if (seen == null || current == null || current <= seen) return 0;
    return current - seen;
  }

  ReadProgress copyWith({int? replies, int? position}) => ReadProgress(
        replies: replies ?? this.replies,
        position: position ?? this.position,
      );

  bool get isEmpty => replies == null && position == null;
}

/// Remembers which posts have been opened, so a list can tell read from
/// unread across restarts — and, for each, how many replies it had then and
/// how far down the reader got, so a list can say what is new and a thread
/// can pick up where it was left.
///
/// Entries are kept newest-first and capped, because this only needs to cover
/// what a person could plausibly still recognise, not their whole history.
class ReadLog {
  ReadLog._(this._keys, [Map<String, ReadProgress>? progress])
      : _progress = progress ?? const {};

  static const _prefsKey = 'readTopics';

  /// Kept under a key of its own, beside the list rather than inside it, so a
  /// build from before this existed still reads the list it knows.
  static const _progressKey = 'readProgress';
  static const limit = 4000;

  /// Loaded once before the first frame, like the rest of the settings.
  static ReadLog bootstrap = ReadLog._(<String>[]);

  final List<String> _keys;
  final Map<String, ReadProgress> _progress;
  late final Set<String> _index = _keys.toSet();

  static String keyFor(SiteId site, String id) => '${site.name}:$id';

  bool contains(SiteId site, String id) => _index.contains(keyFor(site, id));

  ReadProgress? progressOf(SiteId site, String id) =>
      _progress[keyFor(site, id)];

  /// How many replies a topic has had since it was last read. Zero for one
  /// never read, or read before replies were counted.
  int newReplies(SiteId site, String id, int? current) =>
      progressOf(site, id)?.newSince(current) ?? 0;

  int get length => _keys.length;

  /// Roughly what this takes up once stored: the keys plus the separator each
  /// one needs, and the progress beside them. Close enough for a bar that is
  /// measuring gigabytes elsewhere.
  int get storedBytes =>
      _keys.fold(0, (n, key) => n + key.length + 1) +
      _progress.keys.fold(0, (n, key) => n + key.length + 12);

  /// Marks a post read. Returns a new log, or this one when nothing changed.
  ReadLog markRead(SiteId site, String id) {
    final key = keyFor(site, id);
    if (_keys.isNotEmpty && _keys.first == key) return this;
    // A fresh list: this log is the state someone may still be holding.
    final next = <String>[key, for (final k in _keys) if (k != key) k];
    if (next.length > limit) next.removeRange(limit, next.length);
    return ReadLog._(next, _pruned(next, _progress));
  }

  /// Records what has been seen of a post already in the log: how many
  /// replies it had, where the reader was. A post not in the log is left
  /// alone — it is marked read first, which is what puts it there.
  ReadLog withProgress(SiteId site, String id,
      {int? replies, int? position}) {
    final key = keyFor(site, id);
    if (!_index.contains(key)) return this;
    final before = _progress[key] ?? const ReadProgress();
    final after = before.copyWith(replies: replies, position: position);
    if (after.replies == before.replies && after.position == before.position) {
      return this;
    }
    return ReadLog._(_keys, {..._progress, key: after});
  }

  ReadLog cleared() => ReadLog._(<String>[]);

  static Map<String, ReadProgress> _pruned(
      List<String> keys, Map<String, ReadProgress> progress) {
    if (progress.length <= keys.length) {
      final kept = keys.toSet();
      if (progress.keys.every(kept.contains)) return progress;
    }
    final kept = keys.toSet();
    return {
      for (final e in progress.entries)
        if (kept.contains(e.key)) e.key: e.value,
    };
  }

  static Future<ReadLog> load() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getStringList(_prefsKey) ?? <String>[];
    final progress = <String, ReadProgress>{};
    for (final line in prefs.getStringList(_progressKey) ?? const <String>[]) {
      final parts = line.split('\t');
      if (parts.length != 3) continue;
      final entry = ReadProgress(
        replies: int.tryParse(parts[1]),
        position: int.tryParse(parts[2]),
      );
      if (!entry.isEmpty) progress[parts[0]] = entry;
    }
    return ReadLog._(keys, _pruned(keys, progress));
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setStringList(_prefsKey, _keys),
      prefs.setStringList(_progressKey, [
        for (final MapEntry(:key, :value) in _progress.entries)
          '$key\t${value.replies ?? ''}\t${value.position ?? ''}',
      ]),
    ]);
  }
}
