import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../core/disk_cache.dart';

/// A picture that is kept on disk once fetched.
///
/// Being an [ImageProvider] rather than a widget is the point: Flutter's own
/// image cache is keyed on these, so a face already decoded is reused from
/// memory, one fetched earlier comes off the disk, and only a genuinely new
/// address reaches the network. The old path had neither — a proxied picture
/// was re-fetched by every widget that mounted, and nothing survived a
/// restart.
@immutable
class CachedImage extends ImageProvider<CachedImage> {
  const CachedImage(this.url, {this.loader});

  /// The address to fetch, already put through any proxy rewriting.
  final Uri url;

  /// How a site fetches its own pictures, for one that cannot be reached by
  /// an ordinary request. May answer null for an address that can.
  final Future<Uint8List>? Function(Uri url)? loader;

  // Keyed on the address alone. The same bytes arrive whichever way they were
  // fetched, so a picture already on disk should not be fetched again just
  // because a proxy was switched on since.
  @override
  bool operator ==(Object other) => other is CachedImage && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  Future<CachedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CachedImage>(this);

  @override
  ImageStreamCompleter loadImage(
          CachedImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _load(key, decode),
        scale: 1,
        debugLabel: key.url.toString(),
      );

  /// A failure is deliberately left in Flutter's cache rather than evicted.
  /// Dropping the key would let the next build try again, and the next: an
  /// address that is simply gone would be fetched for as long as it stayed on
  /// screen. It is remembered as failed, and the caller draws its placeholder.
  Future<ui.Codec> _load(CachedImage key, ImageDecoderCallback decode) async {
    final stored = await DiskCache.instance.read(key.url);
    if (stored != null) {
      return decode(await ui.ImmutableBuffer.fromUint8List(stored));
    }
    final bytes = await _fetch(key.url);
    unawaited(DiskCache.instance.write(key.url, bytes));
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  /// Shared, and never closed: a page of a feed asks for dozens of pictures
  /// from the same few hosts, and a client per picture would pay a fresh TCP
  /// and TLS handshake for each of them — exactly the cost this cache exists
  /// to remove. The timeout is what keeps a host that accepts a connection
  /// and then says nothing from leaving a picture pending for ever.
  static final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 30);

  Future<Uint8List> _fetch(Uri target) async {
    final bySite = loader?.call(target);
    if (bySite != null) return bySite;
    final request = await _client.getUrl(target);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw NetworkImageLoadException(
          statusCode: response.statusCode, uri: target);
    }
    return consolidateHttpClientResponseBytes(response);
  }
}
