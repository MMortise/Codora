import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Remembers which posts have been opened, so a list can tell read from
/// unread across restarts.
///
/// Entries are kept newest-first and capped, because this only needs to cover
/// what a person could plausibly still recognise, not their whole history.
class ReadLog {
  ReadLog._(this._keys);

  static const _prefsKey = 'readTopics';
  static const limit = 4000;

  /// Loaded once before the first frame, like the rest of the settings.
  static ReadLog bootstrap = ReadLog._(<String>[]);

  final List<String> _keys;
  late final Set<String> _index = _keys.toSet();

  static String keyFor(SiteId site, String id) => '${site.name}:$id';

  bool contains(SiteId site, String id) => _index.contains(keyFor(site, id));

  int get length => _keys.length;

  /// Marks a post read. Returns a new log, or this one when nothing changed.
  ReadLog markRead(SiteId site, String id) {
    final key = keyFor(site, id);
    if (_keys.isNotEmpty && _keys.first == key) return this;
    final next = <String>[key, ...(_keys..remove(key))];
    if (next.length > limit) next.removeRange(limit, next.length);
    return ReadLog._(next);
  }

  ReadLog cleared() => ReadLog._(<String>[]);

  static Future<ReadLog> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ReadLog._(prefs.getStringList(_prefsKey) ?? <String>[]);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _keys);
  }
}
