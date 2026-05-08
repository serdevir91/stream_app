import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'base_addon.dart';

class StremioRemoteAddon extends BaseAddon {
  final String baseUrl;
  final Map<String, dynamic> rawManifest;
  final String? tmdbAccessToken;

  static final Map<String, String> _imdbCache = {};

  StremioRemoteAddon({
    required this.baseUrl,
    required AddonManifest manifest,
    this.rawManifest = const {},
    this.tmdbAccessToken,
  }) : _manifest = manifest;

  final AddonManifest _manifest;

  @override
  AddonManifest get manifest => _manifest;

  @override
  Future<List<SearchResult>> search(String query, String contentType) async {
    final allowedTypes =
        contentType == 'series' ? ['series', 'tv'] : ['movie'];
    final catalogTargets = _catalogTargets(allowedTypes);
    final results = <SearchResult>[];
    final seenIds = <String>{};

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json, */*',
        },
      ));

      for (final target in catalogTargets) {
        final catalogType = target.$1;
        final catalogId = target.$2;
        final endpoints = _catalogEndpoints(catalogType, catalogId, query);

        for (final endpoint in endpoints) {
          try {
            final response = await dio.get(endpoint);
            if (response.statusCode != 200) continue;

            final data = response.data as Map<String, dynamic>;
            final metas = data['metas'] as List? ?? [];

            for (final meta in metas.take(40)) {
              if (meta is! Map) continue;
              final mediaId = (meta['id'] ?? '').toString().trim();
              if (mediaId.isEmpty || seenIds.contains(mediaId)) continue;
              seenIds.add(mediaId);

              final rawType = (meta['type'] ?? catalogType).toString().toLowerCase();
              final mappedType =
                  rawType == 'series' || rawType == 'tv' ? 'series' : 'movie';

              results.add(SearchResult(
                id: mediaId,
                title: (meta['name'] ?? meta['title'] ?? 'Unknown').toString(),
                type: mappedType,
                year: (meta['releaseInfo'] ?? meta['year'] ?? '').toString(),
                poster: meta['poster']?.toString(),
                description: meta['description']?.toString(),
              ));
            }

            if (results.isNotEmpty) break;
          } catch (_) {}
        }
        if (results.isNotEmpty) break;
      }
    } catch (e) {
      debugPrint('[Stremio:${_manifest.id}] Search error: $e');
    }

    return results;
  }

  @override
  Future<List<StreamResult>> getStreams(
    String contentId,
    String contentType,
    int season,
    int episode,
  ) async {
    final candidateIds = await _candidateIds(contentId, contentType);
    final streamTypes =
        contentType == 'series' ? ['series', 'tv'] : ['movie'];

    final streams = <StreamResult>[];
    final seenUrls = <String>{};

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json, */*',
        },
      ));

      for (final stype in streamTypes) {
        for (final candidateId in candidateIds) {
          final streamIds = stype == 'series' || stype == 'tv'
              ? ['$candidateId:$season:$episode', candidateId]
              : [candidateId];

          for (final streamId in streamIds) {
            final endpoint = '$baseUrl/stream/$stype/$streamId.json';
            try {
              final response = await dio.get(endpoint);
              if (response.statusCode != 200) continue;

              final data = response.data as Map<String, dynamic>;
              for (final stream in _parseStremioStreams(data)) {
                if (seenUrls.contains(stream.url)) continue;
                seenUrls.add(stream.url);
                streams.add(stream);
              }

              if (streams.isNotEmpty) return streams;
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[Stremio:${_manifest.id}] Stream error: $e');
    }

    return streams;
  }

  List<(String, String)> _catalogTargets(List<String> allowedTypes) {
    final targets = <(String, String)>[];
    final catalogs = rawManifest['catalogs'];

    if (catalogs is List) {
      for (final catalog in catalogs) {
        if (catalog is! Map) continue;
        final catalogType = (catalog['type'] ?? '').toString().toLowerCase().trim();
        final catalogId = (catalog['id'] ?? '').toString().trim();
        if (catalogId.isEmpty || !allowedTypes.contains(catalogType)) continue;
        targets.add((catalogType, catalogId));
      }
    }

    if (targets.isEmpty) {
      targets.add((allowedTypes.first, 'top'));
    }

    return targets;
  }

  List<String> _catalogEndpoints(
    String catalogType,
    String catalogId,
    String query,
  ) {
    final encoded = Uri.encodeComponent(query.trim());
    final endpoints = <String>[];

    if (encoded.isNotEmpty) {
      endpoints.addAll([
        '$baseUrl/catalog/$catalogType/$catalogId/search=$encoded.json',
        '$baseUrl/catalog/$catalogType/$catalogId.json?search=$encoded',
        '$baseUrl/catalog/$catalogType/$catalogId.json?query=$encoded',
      ]);
    }

    endpoints.add('$baseUrl/catalog/$catalogType/$catalogId.json');
    return endpoints;
  }

  Future<List<String>> _candidateIds(
    String contentId,
    String contentType,
  ) async {
    final raw = contentId.trim();
    final results = <String>[];

    if (raw.startsWith('tt')) {
      results.add(raw);
    } else if (raw.startsWith('tmdb:')) {
      final tmdbId = raw.split(':')[1];
      final imdbId = await tmdbToImdb(tmdbId, contentType);
      if (imdbId != null) results.add(imdbId);
    } else if (RegExp(r'^\d+$').hasMatch(raw)) {
      final imdbId = await tmdbToImdb(raw, contentType);
      if (imdbId != null) results.add(imdbId);
    }

    final imdbMatch = RegExp(r'tt\d+').firstMatch(raw);
    if (imdbMatch != null && !results.contains(imdbMatch.group(0))) {
      results.add(imdbMatch.group(0)!);
    }

    if (raw.isNotEmpty && !results.contains(raw)) {
      results.add(raw);
    }

    return results;
  }

  List<StreamResult> _parseStremioStreams(Map<String, dynamic> payload) {
    final parsed = <StreamResult>[];
    final streamsList = payload['streams'] as List? ?? [];

    for (final stream in streamsList) {
      if (stream is! Map) continue;

      var streamUrl = (stream['url'] ?? stream['externalUrl'])?.toString();

      if (streamUrl == null && stream['ytId'] != null) {
        streamUrl = 'https://www.youtube.com/watch?v=${stream['ytId']}';
      }

      if (streamUrl == null) {
        final infoHash = stream['infoHash']?.toString();
        if (infoHash != null) {
          final displayName =
              (stream['title'] ?? stream['name'] ?? _manifest.name).toString();
          streamUrl =
              'magnet:?xt=urn:btih:$infoHash&dn=${Uri.encodeComponent(displayName)}';
        }
      }

      if (streamUrl == null) continue;

      final titleParts = <String>[];
      if (stream['name'] != null) titleParts.add(stream['name'].toString());
      if (stream['title'] != null) titleParts.add(stream['title'].toString());

      var title = titleParts.where((p) => p.isNotEmpty).join(' - ').trim();
      if (title.isEmpty) title = _manifest.name;

      parsed.add(StreamResult(
        url: streamUrl,
        title: title.length > 140 ? title.substring(0, 140) : title,
        quality: (stream['name'] ?? '').toString().length > 60
            ? stream['name'].toString().substring(0, 60)
            : stream['name']?.toString(),
        provider: _manifest.name,
        isDirectLink: streamUrl.startsWith('magnet:') ||
            streamUrl.contains('.m3u8') ||
            streamUrl.contains('.mp4'),
      ));
    }

    return parsed;
  }

  Future<String?> tmdbToImdb(String tmdbId, String contentType) async {
    final cacheKey = '$contentType:$tmdbId';
    if (_imdbCache.containsKey(cacheKey)) return _imdbCache[cacheKey];

    final token = tmdbAccessToken;
    if (token == null || token.isEmpty) return null;

    try {
      final mediaType =
          contentType == 'series' || contentType == 'tv' ? 'tv' : 'movie';
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Authorization': 'Bearer $token'},
      ));

      final response = await dio
          .get('https://api.themoviedb.org/3/$mediaType/$tmdbId/external_ids');
      final imdbId = response.data['imdb_id']?.toString();
      if (imdbId != null && imdbId.isNotEmpty) {
        _imdbCache[cacheKey] = imdbId;
        return imdbId;
      }
    } catch (e) {
      debugPrint('[TMDB] Lookup error for $tmdbId: $e');
    }
    return null;
  }
}
