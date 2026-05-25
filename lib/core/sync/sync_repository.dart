import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class SyncRequestException implements Exception {
  final String message;

  const SyncRequestException(this.message);

  @override
  String toString() => message;
}

class SyncRepository {
  final Dio _dio;
  final String baseUrl;

  SyncRepository({
    required this.baseUrl,
    String? authToken,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 30),
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           connectTimeout: connectTimeout,
           receiveTimeout: receiveTimeout,
           headers: {
             if (authToken != null) 'Authorization': 'Bearer $authToken',
             'Content-Type': 'application/json',
           },
         ),
       );

  Future<Map<String, dynamic>> registerDevice({
    required String deviceId,
    required String deviceName,
    required String tmdbAccessToken,
  }) async {
    try {
      final response = await _dio.post(
        '/api/sync/register',
        data: {
          'device_id': deviceId,
          'device_name': deviceName,
          'tmdb_token': tmdbAccessToken,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      final readable = _buildReadableError(e);
      debugPrint('Sync register failed: $readable');
      throw SyncRequestException(readable);
    }
  }

  Future<Map<String, dynamic>> pushChanges({
    required String deviceId,
    required List<Map<String, dynamic>> watchHistory,
    required List<Map<String, dynamic>> library,
    required List<String> deletedIds,
    required int sinceMs,
  }) async {
    try {
      final response = await _dio.post(
        '/api/sync/push',
        data: {
          'device_id': deviceId,
          'watch_history': watchHistory,
          'library': library,
          'deleted_ids': deletedIds,
          'since_ms': sinceMs,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      final readable = _buildReadableError(e);
      debugPrint('Sync push failed: $readable');
      throw SyncRequestException(readable);
    }
  }

  Future<Map<String, dynamic>> pullChanges({
    required String deviceId,
    required int sinceMs,
  }) async {
    try {
      final response = await _dio.get(
        '/api/sync/pull',
        queryParameters: {'device_id': deviceId, 'since_ms': sinceMs},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      final readable = _buildReadableError(e);
      debugPrint('Sync pull failed: $readable');
      throw SyncRequestException(readable);
    }
  }

  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get('/api/sync/status');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String _buildReadableError(DioException e) {
    final status = e.response?.statusCode;
    final detail = _extractResponseDetail(e.response?.data);
    final target = _requestTarget(e);

    if (status != null) {
      final suffix = detail == null ? '' : ' - $detail';
      return 'Sunucu hatasi ($status) [$target]$suffix';
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Baglanti zaman asimi [$target]. Sunucu/port ulasilabilirligini kontrol edin.';
    }

    if (e.type == DioExceptionType.connectionError) {
      return 'Sunucuya baglanilamadi [$target]. IP, port veya firewall ayarini kontrol edin.';
    }

    return e.message ?? 'Bilinmeyen baglanti hatasi [$target]';
  }

  String _requestTarget(DioException e) {
    final uri = e.requestOptions.uri;
    final portPart = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$portPart';
  }

  String? _extractResponseDetail(dynamic data) {
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }
    return null;
  }
}
