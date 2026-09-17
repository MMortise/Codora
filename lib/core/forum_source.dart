import 'dart:typed_data';

import 'models.dart';

/// Everything the UI needs from a forum. The shell, the list, the detail pane
/// and the settings page are written against this interface only — adding a
/// site means adding an implementation and registering it, with no changes to
/// any widget.
abstract class ForumSource {
  SiteId get id;
  String get name;

  /// One or two characters standing in for the site when its logo cannot be
  /// drawn (e.g. `V2`, `LD`, `掘`).
  String get glyph;

  /// Bundled logo, shown in the rail and on the settings card.
  String get iconAsset;

  Uri get homeUrl;

  /// One line describing how this site is read, shown on the settings card.
  String get accessNote;

  /// Current reach of the stored credentials.
  SiteAccess get access;

  /// Sections shown as blocks. May hit the network (categories/nodes).
  Future<List<Section>> sections();

  Future<PageResult<TopicSummary>> fetchTopics(Section section, {String? cursor});

  Future<TopicDetail> fetchTopic(String topicId);

  Future<PageResult<Reply>> fetchReplies(String topicId, {String? cursor});

  /// How this site's pictures are reached. Most sites need nothing here.
  ///
  /// Implementations should hand back the same instance every time: the image
  /// widgets restart a load when it changes, so a fresh object per call would
  /// refetch every avatar on every rebuild.
  SiteImages get images => SiteImages.plain;

  /// If [uri] points at a topic on this site, return its id.
  String? topicIdFromUrl(Uri uri);
}

/// How a site's pictures are fetched.
///
/// Two ways to depart from a plain `GET`, in the order they apply: the address
/// can be [rewrite]n (a proxy), and the bytes can be fetched by something
/// other than the network stack via [loader] — which is what a site behind a
/// browser challenge needs.
class SiteImages {
  const SiteImages({this.loader, this.rewrite});

  /// A site whose pictures load with an ordinary request.
  static const plain = SiteImages();

  /// Asked per URL, and may return null meaning "a plain request reaches this
  /// one". That matters for forums serving posts from a protected domain but
  /// their pictures from an open CDN.
  final Future<Uint8List>? Function(Uri url)? loader;

  final Uri Function(Uri url)? rewrite;

  /// The address to actually request for [raw].
  Uri url(Uri raw) => rewrite?.call(raw) ?? raw;

  /// The same pictures fetched directly, for a reader who wants the proxy for
  /// the site but not for everything it links.
  SiteImages get unproxied =>
      rewrite == null ? this : SiteImages(loader: loader);
}
