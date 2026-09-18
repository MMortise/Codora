import 'dart:typed_data';

import 'models.dart';

/// Everything the UI needs from a forum. The shell, the list, the detail pane
/// and the settings page are written against this interface only — adding a
/// site means adding an implementation and registering it, with no changes to
/// any widget.
/// How long a profile card waits for a site before saying so.
///
/// The feed can spend the client's usual fifteen seconds connecting and
/// thirty reading: someone who asked for a page will wait for it. A card that
/// opened because the pointer paused cannot — long before those fire the
/// reader has moved on, having watched a spinner and learnt nothing. Every
/// site is held to the same number, so no card can be the one that hangs.
const kMemberDeadline = Duration(seconds: 8);

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

  /// How to read who the stored credentials sign the reader in as, or null
  /// when this site cannot say.
  ///
  /// Whatever it answers, it answers within [kMemberDeadline] or explains
  /// why it could not.
  ///
  /// A field rather than a method because the rail has to know whether to
  /// offer a card before it goes and fetches one — and because the answer
  /// turns on the credentials, not on the site: V2EX can only do this with a
  /// token, and hands back null without one.
  Future<Member> Function()? get member => null;

  /// How to answer a topic, or null when this site cannot be written to —
  /// either it has no way in, or the stored credentials do not sign the
  /// reader in.
  ///
  /// A field for the same reason as [member]: the reading pane has to know
  /// whether to offer a box before anyone types in it, and asking would mean
  /// a request.
  ///
  /// It answers with the reply the site made of the text, not with nothing:
  /// the pane puts that at the end of the thread rather than reloading, which
  /// would take the reader back to the first page of something they had
  /// scrolled through, with their own words the part not loaded.
  Future<Reply> Function(String topicId, String text)? get reply => null;

  /// How to like a post, or null where the site has no such thing — or the
  /// stored credentials do not sign the reader in.
  ///
  /// A field for the same reason as [reply]. It answers with where the post
  /// stands afterwards rather than with nothing, because the count it comes
  /// back with is the site's, not one the app worked out by adding one.
  Future<LikeState> Function(String postId, {required bool like})? get like =>
      null;

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
}
