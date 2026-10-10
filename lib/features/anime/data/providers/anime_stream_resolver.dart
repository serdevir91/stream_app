import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/anime_item.dart';
import '../../domain/models/anime_extension.dart';
import '../../../../core/backend/addon_service.dart';

class AnimeStreamResolver {
  final AddonService? addonService;
  final String? tmdbAccessToken;
  final Dio _dio;

  AnimeStreamResolver({
    this.addonService,
    this.tmdbAccessToken,
  }) : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 10),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
              'Accept': 'application/json, text/html, */*',
            },
          ),
        );

  /// Resolves all available streaming sources for an anime episode
  Future<List<Map<String, dynamic>>> resolveEpisodeStreams({
    required AnimeItem anime,
    required int episodeNumber,
    int seasonNumber = 1,
    List<AnimeExtension>? extensions,
  }) async {
    final streams = <Map<String, dynamic>>[];
    final seenUrls = <String>{};

    bool isExtEnabled(String extId) {
      if (extensions == null || extensions.isEmpty) return true;
      final found = extensions.firstWhere(
        (e) => e.id == extId,
        orElse: () => AnimeExtension(id: extId, name: '', description: '', isEnabled: true),
      );
      return found.isEnabled;
    }

    void addStream({
      required String url,
      required String title,
      required String provider,
      String quality = 'HD',
      String addonId = 'builtin.anime',
      bool isDirectLink = false,
      Map<String, String>? headers,
    }) {
      if (url.isEmpty || seenUrls.contains(url)) return;
      seenUrls.add(url);
      streams.add({
        'url': url,
        'title': title,
        'provider': provider,
        'quality': quality,
        'addon_id': addonId,
        'is_direct_link': isDirectLink,
        'headers': ?headers,
      });
    }

    final malId = anime.malId;
    final cleanTitle = anime.englishTitle?.isNotEmpty == true
        ? anime.englishTitle!
        : anime.title;

    // -------------------------------------------------------------
    // 1. Dedicated Anime Embed Providers
    // -------------------------------------------------------------
    if (malId > 0) {
      // 2Embed Anime (Tested HTTP 200)
      if (isExtEnabled('twoembed_anime')) {
        addStream(
          url: 'https://2embed.cc/embed/anime/$malId/$episodeNumber',
          title: '2Embed Anime (Fast)',
          provider: '2Embed Anime',
          quality: '1080p',
          addonId: 'builtin.anime.twoembed',
          isDirectLink: false,
        );
      }

      // AniWave Embed (Tested HTTP 200)
      if (isExtEnabled('aniwave_anime')) {
        addStream(
          url: 'https://aniwave.to/embed/$malId/$episodeNumber',
          title: 'AniWave Embed (HD)',
          provider: 'AniWave',
          quality: '1080p',
          addonId: 'builtin.anime.aniwave',
          isDirectLink: false,
        );
      }

      // VidSrc.cc Anime Player (Multi-Server)
      if (isExtEnabled('vidsrc_anime')) {
        addStream(
          url: 'https://vidsrc.cc/v2/embed/anime/$malId/$episodeNumber',
          title: 'VidSrc Anime (Multi-Server)',
          provider: 'VidSrc Anime',
          quality: '1080p',
          addonId: 'builtin.anime.vidsrc',
          isDirectLink: false,
        );
        addStream(
          url: 'https://vidsrc.to/embed/anime/$malId/$episodeNumber',
          title: 'VidSrc.to Anime (Mirror)',
          provider: 'VidSrc.to',
          quality: '1080p',
          addonId: 'builtin.anime.vidsrcto',
          isDirectLink: false,
        );
      }

      // SmashyStream Anime Player
      if (isExtEnabled('smashy_anime')) {
        addStream(
          url: 'https://player.smashystream.com/anime?id=$malId&ep=$episodeNumber',
          title: 'Smashy Anime Player',
          provider: 'SmashyStream',
          quality: '1080p',
          addonId: 'builtin.anime.smashy',
          isDirectLink: false,
        );
      }

      // MultiEmbed Anime Player
      if (isExtEnabled('multiembed_anime')) {
        addStream(
          url: 'https://multiembed.mov/?video_id=$malId&anime=1&s=$seasonNumber&e=$episodeNumber',
          title: 'MultiEmbed Anime',
          provider: 'MultiEmbed',
          quality: 'HD',
          addonId: 'builtin.anime.multiembed',
          isDirectLink: false,
        );
      }
    }

    // -------------------------------------------------------------
    // 2. GogoAnime / Anitaku Scraper & Player
    // -------------------------------------------------------------
    if (isExtEnabled('gogoanime_direct')) {
      try {
        final gogoSlug = _slugify(cleanTitle);
        if (gogoSlug.isNotEmpty) {
          addStream(
            url: 'https://anitaku.so/$gogoSlug-episode-$episodeNumber',
            title: 'GogoAnime ($gogoSlug)',
            provider: 'GogoAnime',
            quality: 'HD',
            addonId: 'builtin.anime.gogo',
            isDirectLink: false,
          );

          // Also try romaji slug if different
          if (anime.romajiTitle != null && anime.romajiTitle!.isNotEmpty) {
            final romajiSlug = _slugify(anime.romajiTitle!);
            if (romajiSlug.isNotEmpty && romajiSlug != gogoSlug) {
              addStream(
                url: 'https://anitaku.so/$romajiSlug-episode-$episodeNumber',
                title: 'GogoAnime ($romajiSlug)',
                provider: 'GogoAnime',
                quality: 'HD',
                addonId: 'builtin.anime.gogo',
                isDirectLink: false,
              );
            }
          }
        }
      } catch (_) {}
    }

    // -------------------------------------------------------------
    // 3. TMDB Mapping & Existing StreamApp Addons Bridge
    // -------------------------------------------------------------
    if (isExtEnabled('tmdb_bridge')) {
      try {
      final tmdbId = await _resolveTmdbId(anime);
      if (tmdbId != null && addonService != null) {
        final tmdbStreams = await addonService!.resolve(
          query: cleanTitle,
          contentType: 'series',
          season: seasonNumber,
          episode: episodeNumber,
          tmdbId: tmdbId.toString(),
        );

        final addonStreams = (tmdbStreams['streams'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .toList();

        for (final s in addonStreams) {
          final streamUrl = s['url']?.toString() ?? '';
          if (streamUrl.isNotEmpty && !seenUrls.contains(streamUrl)) {
            seenUrls.add(streamUrl);
            streams.add({
              'url': streamUrl,
              'title': s['title'] ?? cleanTitle,
              'provider': s['provider'] ?? 'Stream App Source',
              'quality': s['quality'] ?? 'HD',
              'addon_id': s['addon_id'] ?? 'builtin.tmdb',
              'is_direct_link': s['is_direct_link'] == true,
              if (s['headers'] != null) 'headers': s['headers'],
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[AnimeStreamResolver] TMDB resolve error: $e');
    }
    }

    return streams;
  }

  /// Searches TMDB to find the matching TV show ID
  Future<int?> _resolveTmdbId(AnimeItem anime) async {
    final queryCandidates = <String>[];
    if (anime.englishTitle != null && anime.englishTitle!.trim().isNotEmpty) {
      queryCandidates.add(anime.englishTitle!.trim());
    }
    if (anime.title.trim().isNotEmpty && !queryCandidates.contains(anime.title.trim())) {
      queryCandidates.add(anime.title.trim());
    }
    if (anime.romajiTitle != null && anime.romajiTitle!.trim().isNotEmpty && !queryCandidates.contains(anime.romajiTitle!.trim())) {
      queryCandidates.add(anime.romajiTitle!.trim());
    }

    for (final q in queryCandidates) {
      try {
        final res = await _dio.get(
          'https://api.themoviedb.org/3/search/tv',
          queryParameters: {
            'query': q,
            if (anime.year != null && anime.year! > 0) 'first_air_date_year': anime.year,
          },
          options: Options(
            headers: {
              if (tmdbAccessToken != null && tmdbAccessToken!.trim().isNotEmpty)
                'Authorization': 'Bearer ${tmdbAccessToken!.trim()}',
            },
          ),
        );

        if (res.statusCode == 200 && res.data is Map && res.data['results'] is List) {
          final results = res.data['results'] as List;
          if (results.isNotEmpty && results.first is Map && results.first['id'] is int) {
            return results.first['id'] as int;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  String _slugify(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
  }
}
