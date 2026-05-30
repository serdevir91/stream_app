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
    required List<Map<String, dynamic>> watched,
    required Map<String, dynamic>? settings,
    required List<Map<String, dynamic>> sources,
    required Map<String, dynamic>? addonConfig,
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
          'watched': watched,
          'settings': settings,
          'sources': sources,
          'addon_config': addonConfig,
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

    if (status != null) {
      return 'sync_error_server_error';
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'sync_error_timeout';
    }

    if (e.type == DioExceptionType.connectionError) {
      return 'sync_error_cannot_connect_detail';
    }

    return 'sync_error_unknown';
  }
}
