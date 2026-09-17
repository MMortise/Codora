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

  /// Extra headers needed to load this site's images, if any.
  Map<String, String>? get imageHeaders => null;

  /// Sites where some images need special handling return a loader here.
  ///
  /// The loader is asked per URL and may return null, meaning "a plain network
  /// request reaches this one". That matters for forums that serve posts from
  /// a protected domain but their pictures from an open CDN.
  Future<Uint8List>? Function(Uri url)? get imageLoader => null;

  /// If [uri] points at a topic on this site, return its id.
  String? topicIdFromUrl(Uri uri);
}
