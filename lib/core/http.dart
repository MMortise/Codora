import 'package:dio/dio.dart';

import 'proxy.dart';

/// The one HTTP client every site is built on: shared timeouts, headers and
/// the rule that only a 5xx is an exception.
///
/// [proxy], when given, routes everything this client sends through it.
Dio buildDio({
  required String baseUrl,
  Map<String, String>? headers,
  UrlProxy? proxy,
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
  if (proxy != null) dio.interceptors.add(_ProxyInterceptor(proxy));
  return dio;
}

/// Hands the proxy the fully resolved address.
///
/// The rewrite has to happen here, at the last moment, rather than on the base
/// URL: Dio only appends the query string when it builds `options.uri`, so
/// rewriting any earlier would leave `?id=123` dangling outside the address
/// the proxy was given. An absolute path bypasses `baseUrl`, and the query is
/// cleared because it is now part of that path.
class _ProxyInterceptor extends Interceptor {
  _ProxyInterceptor(this.proxy);
  final UrlProxy proxy;

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
