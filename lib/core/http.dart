import 'package:dio/dio.dart';

Dio buildDio({required String baseUrl, Map<String, String>? headers}) {
  return Dio(BaseOptions(
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
