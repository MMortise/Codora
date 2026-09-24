import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// What the cache may use before it starts dropping the oldest pictures.
/// Generous on purpose: a desktop has the room, and a cache that evicts what
/// you are still looking at is worse than one that takes a few gigabytes.
const kDefaultCacheLimit = 10 * 1024 * 1024 * 1024;

/// What saved lists and threads may use. Thousands of threads fit.
const kPagesCacheLimit = 256 * 1024 * 1024;

/// Pictures kept on disk between launches.
///
/// Avatars are the case that matters: a feed shows the same few dozen faces
/// over and over, and without this every scroll — and every launch — fetched
/// all of them again. Through a proxy that is slow enough to see.
///
/// One flat directory of files named after the address they came from. No
/// index: the filesystem already knows the size of a file and when it was
/// last read, which is everything eviction needs, and a separate index is one
/// more thing that can disagree with the truth.
class DiskCache {
  DiskCache._(this.folder, {this.limit = kDefaultCacheLimit});

  static final instance = DiskCache._('images');

  /// Lists and threads, kept so there is something to show before the
  /// network answers — see [Snapshots]. Text is small beside pictures, so it
  /// has a fixed budget of its own rather than a share of theirs: a gallery
  /// of screenshots should not be what pushes the last thread read out.
  static final pages = DiskCache._('pages', limit: kPagesCacheLimit);

  /// The directory under the app's support folder.
  final String folder;

  /// How much the whole cache may use. Set from settings at launch and
  /// whenever the reader changes it.
  int limit;

  /// Trimming has to walk the directory, so it is not worth doing on every
  /// picture. This much has to be written first.
  static const _trimEvery = 16 * 1024 * 1024;
  int _sinceTrim = 0;

  /// Where the pictures go, once [prepare] has found it.
  ///
  /// Asking the platform for a directory is done once, at launch, rather than
  /// on the way to each picture: the answer never changes, and somewhere
  /// without a platform to ask — a test — the question hangs rather than
  /// failing, which would stall every image behind it. Null simply means
  /// there is no cache, and everything falls back to fetching.
  Directory? _dir;

  bool get ready => _dir != null;

  /// Where the pictures are, once opened. The one place in the app that knows
  /// a real path: everything else that needs one builds on this rather than
  /// asking the platform again, which is both slower and — with no platform
  /// to answer — a question that never comes back.
  Directory? get directory => _dir;

  /// Opens the cache and starts bringing it within [budget]. Safe to call
  /// when there is no platform directory to be had; the cache is then a
  /// no-op.
  Future<void> prepare({int? budget}) async {
    if (budget != null) limit = budget;
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/$folder');
      if (!dir.existsSync()) await dir.create(recursive: true);
      _dir = dir;
      // A limit lowered while the app was closed takes effect now rather than
      // after enough new pictures happen to trigger a trim — but nothing
      // waits for it. This runs on the way to the first frame, and walking a
      // full cache to stat every file in it would be the reader watching an
      // empty screen for housekeeping that concerns them not at all.
      unawaited(trimTo(limit));
    } catch (_) {
      _dir = null;
    }
  }

  /// A file name that is stable for an address, safe on every filesystem, and
  /// short enough that a long query string cannot overrun a name limit.
  ///
  /// `utf8.encode` rather than `codeUnits`: the latter hands back UTF-16
  /// units, and a digest that wants bytes would quietly mask anything above
  /// 255 — two addresses differing only in the high byte of a character would
  /// then share a file, and one picture would be served for the other.
  String _name(Uri url) => sha1.convert(utf8.encode(url.toString())).toString();

  File? _fileFor(Uri url) {
    final dir = _dir;
    return dir == null ? null : File('${dir.path}/${_name(url)}');
  }

  Future<Uint8List?> read(Uri url) async {
    try {
      final file = _fileFor(url);
      if (file == null) return null;
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      // Eviction goes by last modified, so reading one keeps it alive. A
      // failure here is not worth losing the picture over.
      try {
        await file.setLastModified(DateTime.now());
      } catch (_) {}
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Uri url, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    try {
      // Written beside the real name and moved into place, so a half-written
      // file can never be read back as a picture.
      final file = _fileFor(url);
      if (file == null) return;
      final partial = File('${file.path}.part');
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(file.path);
      _sinceTrim += bytes.length;
      if (_sinceTrim >= _trimEvery) {
        _sinceTrim = 0;
        unawaited(trimTo(limit));
      }
    } catch (_) {}
  }

  /// Bytes currently on disk.
  Future<int> size() async {
    try {
      final dir = _dir;
      if (dir == null) return 0;
      var total = 0;
      await for (final entry in dir.list()) {
        if (entry is File) total += await entry.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clear() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
      _sinceTrim = 0;
    } catch (_) {}
  }

  /// Drops the least recently read pictures until the rest fit in [limit].
  ///
  /// Least recently *read*, not written: a face that shows up in every thread
  /// should outlive a picture opened once, however new that one is.
  Future<void> trimTo(int limit) async {
    try {
      final dir = _dir;
      if (dir == null) return;
      final files = <(File, DateTime, int)>[];
      var total = 0;
      await for (final entry in dir.list()) {
        if (entry is! File) continue;
        final stat = await entry.stat();
        files.add((entry, stat.modified, stat.size));
        total += stat.size;
      }
      if (total <= limit) return;
      files.sort((a, b) => a.$2.compareTo(b.$2));
      for (final (file, _, size) in files) {
        if (total <= limit) break;
        try {
          await file.delete();
          total -= size;
        } catch (_) {}
      }
    } catch (_) {}
  }
}
