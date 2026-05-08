import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'base_addon.dart';

class RemoteAddon extends BaseAddon {
  final String baseUrl;

  RemoteAddon({
    required this.baseUrl,
    required AddonManifest manifest,
  }) : _manifest = manifest;

  final AddonManifest _manifest;

  @override
  AddonManifest get manifest => _manifest;

  @override
  Future<List<SearchResult>> search(String query, String contentType) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json, */*',
        },
      ));

      final response = await dio.get(
        '$baseUrl/search',
        queryParameters: {'query': query, 'type': contentType},
      );

      final data = response.data as Map<String, dynamic>;
      final results = data['results'] as List? ?? [];
      return results.whereType<Map>().map((item) {
        return SearchResult(
          id: (item['id'] ?? '').toString(),
          title: (item['title'] ?? '').toString(),
          type: (item['type'] ?? contentType).toString(),
          year: item['year']?.toString(),
          poster: item['poster']?.toString(),
          description: item['description']?.toString(),
        );
      }).toList();
    } catch (e) {
      debugPrint('[RemoteAddon:${_manifest.id}] Search error: $e');
      return [];
    }
  }

  @override
  Future<List<StreamResult>> getStreams(
    String contentId,
    String contentType,
    int season,
    int episode,
  ) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json, */*',
        },
      ));

      final response = await dio.get(
        '$baseUrl/stream',
        queryParameters: {
          'id': contentId,
          'type': contentType,
          'season': season,
          'episode': episode,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final streams = data['streams'] as List? ?? [];
      return streams.whereType<Map>().map((item) {
        return StreamResult(
          url: (item['url'] ?? '').toString(),
          title: (item['title'] ?? _manifest.name).toString(),
          quality: item['quality']?.toString(),
          provider: item['provider']?.toString() ?? _manifest.name,
          isDirectLink: item['is_direct_link'] ?? true,
        );
      }).toList();
    } catch (e) {
      debugPrint('[RemoteAddon:${_manifest.id}] Stream error: $e');
      return [];
    }
  }
}
