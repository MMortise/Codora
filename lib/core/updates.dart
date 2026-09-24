import 'package:dio/dio.dart';

/// Where releases are published. The release workflow puts every tagged build
/// here, so the newest one is the newest the app could be.
final kLatestReleaseUrl =
    Uri.parse('https://api.github.com/repos/MMortise/Codora/releases/latest');

/// A published build newer than the one running.
class Release {
  const Release({required this.version, required this.url, this.notes});

  /// As the tag names it, without the leading `v`.
  final String version;

  /// The release's own page, where the download is.
  final Uri url;
  final String? notes;
}

/// Orders two versions of the `1.2.3` kind, ignoring a leading `v` and
/// anything after `+` or `-`.
///
/// Missing parts count as zero, so `1.2` and `1.2.0` are the same version. A
/// part that is not a number counts as zero as well: a tag nobody meant as a
/// version should not be offered as an update.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp('^v'), '')
      .split(RegExp('[+-]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// The newest release, when it is newer than [current]; null when [current]
/// is as new as it gets, or nothing has been published yet.
Future<Release?> newerRelease(String current, {Dio? dio}) async {
  final client = dio ??
      Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Accept': 'application/vnd.github+json'},
      ));
  final Response<Map<String, dynamic>> res;
  try {
    res = await client.getUri<Map<String, dynamic>>(kLatestReleaseUrl);
  } on DioException catch (e) {
    // GitHub answers 404 for a repository with no releases yet.
    if (e.response?.statusCode == 404) return null;
    rethrow;
  }
  final data = res.data ?? const {};
  final tag = data['tag_name'] as String?;
  final page = data['html_url'] as String?;
  if (tag == null || page == null) return null;
  if (compareVersions(tag, current) <= 0) return null;
  return Release(
    version: tag.replaceFirst(RegExp('^v'), ''),
    url: Uri.parse(page),
    notes: data['body'] as String?,
  );
}
