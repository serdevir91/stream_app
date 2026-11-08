import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

/// Caches successful TMDB GET responses in memory and in Hive. Fresh entries
/// skip the network; stale ones are served when the network fails, so home
/// rows still show offline.
class TmdbCacheInterceptor extends Interceptor {
  TmdbCacheInterceptor({this.ttl = const Duration(hours: 6)});

  static const String boxName = 'tmdb_cache_box';
  static const int _maxEntries = 600;

  final Duration ttl;
  final Map<String, ({int at, String body})> _memory = {};

  static Future<void> init() async {
    if (Hive.isBoxOpen(boxName)) return;
    try {
      final box = await Hive.openBox<String>(boxName);
      if (box.length > _maxEntries) {
        // Drop the oldest half; entries are "<epochMs>\n<json>".
        final keys = box.keys.toList()
          ..sort((a, b) => _timeOf(box.get(a)).compareTo(_timeOf(box.get(b))));
        await box.deleteAll(keys.take(box.length - _maxEntries ~/ 2));
      }
    } catch (_) {}
  }

  static int _timeOf(String? raw) {
    if (raw == null) return 0;
    final nl = raw.indexOf('\n');
    return nl < 0 ? 0 : int.tryParse(raw.substring(0, nl)) ?? 0;
  }

  Box<String>? get _box =>
      Hive.isBoxOpen(boxName) ? Hive.box<String>(boxName) : null;

  static bool _cacheable(RequestOptions o) =>
      o.method == 'GET' &&
      o.uri.host == 'api.themoviedb.org' &&
      o.extra['noCache'] != true;

  static String _key(RequestOptions o) => o.uri.toString();

  ({int at, String body})? _lookup(String key) {
    final mem = _memory[key];
    if (mem != null) return mem;
    final raw = _box?.get(key);
    if (raw == null) return null;
    final nl = raw.indexOf('\n');
    if (nl < 0) return null;
    final entry = (at: int.tryParse(raw.substring(0, nl)) ?? 0, body: raw.substring(nl + 1));
    _memory[key] = entry;
    return entry;
  }

  Response<dynamic>? _response(RequestOptions options, String body) {
    try {
      return Response<dynamic>(
        requestOptions: options,
        data: jsonDecode(body),
        statusCode: 200,
        extra: {'fromCache': true},
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_cacheable(options)) {
      final entry = _lookup(_key(options));
      final now = DateTime.now().millisecondsSinceEpoch;
      if (entry != null && now - entry.at < ttl.inMilliseconds) {
        final response = _response(options, entry.body);
        if (response != null) return handler.resolve(response);
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    if (_cacheable(options) &&
        response.statusCode == 200 &&
        response.extra['fromCache'] != true &&
        (response.data is Map || response.data is List)) {
      try {
        final body = jsonEncode(response.data);
        final at = DateTime.now().millisecondsSinceEpoch;
        final key = _key(options);
        _memory[key] = (at: at, body: body);
        if (_memory.length > 300) _memory.remove(_memory.keys.first);
        _box?.put(key, '$at\n$body');
      } catch (_) {}
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    final offline = err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout;
    if (offline && _cacheable(options)) {
      final entry = _lookup(_key(options));
      final response = entry == null ? null : _response(options, entry.body);
      if (response != null) return handler.resolve(response);
    }
    handler.next(err);
  }
}
