import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'proxy.dart';

/// The one HTTP client every site is built on: shared timeouts, headers and
/// the rule that only a 5xx is an exception.
///
/// [proxy], when given, routes everything this client sends through it.
Dio buildDio({
  required String baseUrl,
  Map<String, String>? headers,
  SiteProxy? proxy,
}) {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      ...?headers,
    },
    responseType: ResponseType.json,
    validateStatus: (s) => s != null && s < 500,
  ));
  switch (proxy) {
    case null:
      break;
    // The client itself is pointed at the proxy, exactly as HTTP_PROXY does
    // it, so HTTPS goes through CONNECT and the site sees a normal request.
    case ProxyTunnel(:final proxyString):
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => HttpClient()..findProxy = (_) => proxyString,
      );
    case ProxyRewrite p:
      dio.interceptors.add(_RewriteInterceptor(p));
  }
  return dio;
}

/// Hands a rewriting proxy the fully resolved address.
///
/// The rewrite has to happen here, at the last moment, rather than on the base
/// URL: Dio only appends the query string when it builds `options.uri`, so
/// rewriting any earlier would leave `?id=123` dangling outside the address
/// the proxy was given. An absolute path bypasses `baseUrl`, and the query is
/// cleared because it is now part of that path.
class _RewriteInterceptor extends Interceptor {
  _RewriteInterceptor(this.proxy);
  final ProxyRewrite proxy;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.path = proxy.applyTo(options.uri.toString());
    options.queryParameters = const {};
    handler.next(options);
  }
}

int? asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

DateTime? fromUnixSeconds(Object? v) {
  final n = asInt(v);
  if (n == null || n <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(n * 1000);
}

DateTime? fromIso(Object? v) => v == null ? null : DateTime.tryParse('$v');
