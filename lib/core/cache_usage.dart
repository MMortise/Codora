import 'dart:io';

import 'disk_cache.dart';
import 'read_log.dart';

/// The kinds of thing the app leaves on disk, in the order they are worth
/// looking at: the one that grows without bound, the lists and threads kept
/// for reading offline, the one a site fills in on its own, and the one that
/// is the reader's own history.
enum CacheKind {
  images('图片', '头像和帖子里的图，按地址存，最久没看的先丢'),
  pages('帖子', '最近看过的列表和帖子。打开时先显示它们，连不上站点时也能看。'
      '最多 256 MB，最久没看的先丢'),
  web('网页数据', 'linux.do 的内置浏览器留下的验证、Cookie 和页面缓存。'
      '清理时只会清掉其中的页面缓存'),
  readLog('阅读记录', '哪些帖子读过。很小，但它也占着地方');

  const CacheKind(this.label, this.note);

  final String label;
  final String note;
}

/// What is on disk right now, and how much room there is for it.
class CacheReport {
  const CacheReport({
    required this.sizes,
    required this.limit,
    required this.capacity,
  });

  final Map<CacheKind, int> sizes;

  /// What the reader has allowed the cache to use.
  final int limit;

  /// The size of the disk it all sits on, which is as high as a limit can
  /// sensibly go.
  final int capacity;

  int get total => sizes.values.fold(0, (a, b) => a + b);

  int of(CacheKind kind) => sizes[kind] ?? 0;

  static const empty = CacheReport(
    sizes: {},
    limit: kDefaultCacheLimit,
    capacity: kFallbackCapacity,
  );
}

/// Stands in for the disk when its real size cannot be read. High enough not
/// to get in anyone's way, and only ever used as the top of a slider.
const kFallbackCapacity = 512 * 1024 * 1024 * 1024;

/// The app's own `Library`, worked out from the cache's directory.
///
/// That is `<Library>/Application Support/<id>/images`, so the ancestor three
/// levels up is the folder WebKit keeps its own storage beside. Null before
/// the cache has been opened — in a test, say — and the callers then report
/// nothing rather than guessing.
Directory? _libraryDir() {
  final images = DiskCache.instance.directory;
  return images?.parent.parent.parent;
}

/// Adds up what each kind is using.
///
/// Every part is best-effort: a directory that cannot be read counts as
/// nothing rather than failing the whole report, because a settings page that
/// refuses to draw is worse than one that under-counts.
Future<CacheReport> measureCache(int limit) async {
  final images = await DiskCache.instance.size();
  final pages = await DiskCache.pages.size();
  final web = await _webDataSize();
  return CacheReport(
    sizes: {
      CacheKind.images: images,
      CacheKind.pages: pages,
      CacheKind.web: web,
      CacheKind.readLog: ReadLog.bootstrap.storedBytes,
    },
    limit: limit,
    capacity: await diskCapacity(),
  );
}

/// What WebKit has kept for the sites the app opened in a browser.
///
/// It lives beside the app's own storage rather than inside it, so the path
/// is walked up to from somewhere path_provider does know. If the layout is
/// not what is expected, this reports nothing rather than guessing.
Future<int> _webDataSize() async {
  final library = _libraryDir();
  if (library == null) return 0;
  try {
    var total = 0;
    for (final name in const ['WebKit', 'Caches/WebKit', 'Cookies']) {
      total += await _sizeOf(Directory('${library.path}/$name'));
    }
    return total;
  } catch (_) {
    return 0;
  }
}

Future<int> _sizeOf(Directory dir) async {
  if (!dir.existsSync()) return 0;
  var total = 0;
  try {
    await for (final entry in dir.list(recursive: true, followLinks: false)) {
      if (entry is File) {
        try {
          total += await entry.length();
        } catch (_) {}
      }
    }
  } catch (_) {}
  return total;
}

/// The size of the disk the cache sits on.
///
/// Dart has no API for this, so it comes from `df`. A sandboxed app may not
/// be allowed to run it, and nothing here is important enough to fail over —
/// [kFallbackCapacity] stands in when it does not work.
Future<int> diskCapacity() async {
  final here = DiskCache.instance.directory;
  if (here == null) return kFallbackCapacity;
  try {
    final out = await Process.run('df', ['-k', here.path]);
    final lines = '${out.stdout}'.trim().split('\n');
    if (lines.length < 2) return kFallbackCapacity;
    final blocks = lines[1].split(RegExp(r'\s+'));
    final kb = int.tryParse(blocks.length > 1 ? blocks[1] : '');
    return kb == null ? kFallbackCapacity : kb * 1024;
  } catch (_) {
    return kFallbackCapacity;
  }
}

/// Bytes as someone would say them: "1.4 GB", "860 MB".
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  // Whole numbers below a kilobyte, and one decimal only where it says
  // something — "1.0 GB" is noise where "1 GB" is not.
  final rounded = value >= 100 || unit == 0 || value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '$rounded ${units[unit]}';
}
