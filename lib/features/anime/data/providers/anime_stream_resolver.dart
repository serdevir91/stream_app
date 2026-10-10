import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/anime_item.dart';
import '../../domain/models/anime_extension.dart';
import '../../../../core/backend/addon_service.dart';

class AnimeStreamResolver {
  final AddonService? addonService;
  final String? tmdbAccessToken;
  final Dio _dio;

  // Cache resolved slugs & anilist IDs to speed up subsequent episode lookups
  final Map<int, String> _slugCache = {};
  final Map<int, int> _anilistIdCache = {};
  final Map<int, int> _tmdbIdCache = {};

  AnimeStreamResolver({
    this.addonService,
    this.tmdbAccessToken,
  }) : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 7),
            receiveTimeout: const Duration(seconds: 9),
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
      List<Map<String, dynamic>>? subtitles,
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
        if (subtitles != null && subtitles.isNotEmpty) 'subtitles': subtitles,
      });
    }

    final malId = anime.malId;
    final cleanTitle = anime.englishTitle?.isNotEmpty == true
        ? anime.englishTitle!
        : anime.title;

    // -------------------------------------------------------------
    // Pre-resolve Subtitles from Altyazı Arşivi
    // -------------------------------------------------------------
    List<Map<String, dynamic>> subtitleTracks = const [];
    if (isExtEnabled('altyazi_arsivi')) {
      try {
        subtitleTracks = await _resolveAltyaziArsiviSubtitles(anime, episodeNumber);
      } catch (e) {
        debugPrint('[AnimeStreamResolver] Subtitle error: $e');
      }
    }

    // -------------------------------------------------------------
    // 1. OpenAnime Native Resolver (Direct MP4 Streams - pixiAndroid)
    // -------------------------------------------------------------
    if (isExtEnabled('openani')) {
      try {
        final openAniSources = await _resolveOpenAnimeSources(
          anime: anime,
          episodeNumber: episodeNumber,
          seasonNumber: seasonNumber,
        );

        for (final src in openAniSources) {
          addStream(
            url: src['url'] as String,
            title: src['title'] as String,
            provider: 'OpenAnime',
            quality: src['quality'] as String? ?? 'HD',
            addonId: 'builtin.anime.openani',
            isDirectLink: true,
            subtitles: subtitleTracks,
          );
        }
      } catch (e) {
        debugPrint('[AnimeStreamResolver] OpenAnime error: $e');
      }
    }

    // -------------------------------------------------------------
    // 2. TMDB TV Bridge (Cross-Resolves to Multi-Servers)
    // -------------------------------------------------------------
    int? tmdbId;
    if (isExtEnabled('tmdb_bridge') || isExtEnabled('vidsrc_anime') || isExtEnabled('twoembed_anime')) {
      try {
        tmdbId = await _resolveTmdbId(anime);
      } catch (e) {
        debugPrint('[AnimeStreamResolver] TMDB lookup error: $e');
      }
    }

    if (tmdbId != null && isExtEnabled('tmdb_bridge')) {
      final isMovie = anime.isMovie;
      // AutoEmbed Player
      addStream(
        url: isMovie
            ? 'https://player.autoembed.cc/embed/movie/$tmdbId'
            : 'https://player.autoembed.cc/embed/tv/$tmdbId/$seasonNumber/$episodeNumber',
        title: 'AutoEmbed ($cleanTitle)',
        provider: 'AutoEmbed',
        quality: '1080p',
        addonId: 'builtin.anime.autoembed',
        isDirectLink: false,
        subtitles: subtitleTracks,
      );

      // VidSrc.to Player
      addStream(
        url: isMovie
            ? 'https://vidsrc.to/embed/movie/$tmdbId'
            : 'https://vidsrc.to/embed/tv/$tmdbId/$seasonNumber/$episodeNumber',
        title: isMovie ? 'VidSrc.to Movie ($cleanTitle)' : 'VidSrc.to TV ($cleanTitle)',
        provider: 'VidSrc.to',
        quality: '1080p',
        addonId: 'builtin.anime.vidsrcto',
        isDirectLink: false,
        subtitles: subtitleTracks,
      );

      // 2Embed Player
      addStream(
        url: isMovie
            ? 'https://www.2embed.cc/embed/movie?id=$tmdbId'
            : 'https://www.2embed.cc/embed/tv?id=$tmdbId&s=$seasonNumber&e=$episodeNumber',
        title: isMovie ? '2Embed Movie ($cleanTitle)' : '2Embed TV ($cleanTitle)',
        provider: '2Embed',
        quality: '1080p',
        addonId: 'builtin.anime.twoembed',
        isDirectLink: false,
        subtitles: subtitleTracks,
      );

      // MultiEmbed Player
      addStream(
        url: isMovie
            ? 'https://multiembed.mov/?video_id=$tmdbId&tmdb=1'
            : 'https://multiembed.mov/?video_id=$tmdbId&tmdb=1&s=$seasonNumber&e=$episodeNumber',
        title: isMovie ? 'MultiEmbed Movie ($cleanTitle)' : 'MultiEmbed TV ($cleanTitle)',
        provider: 'MultiEmbed',
        quality: 'HD',
        addonId: 'builtin.anime.multiembed',
        isDirectLink: false,
        subtitles: subtitleTracks,
      );

      // Also query AddonService if available
      if (addonService != null) {
        try {
          final tmdbStreams = await addonService!.resolve(
            query: cleanTitle,
            contentType: isMovie ? 'movie' : 'series',
            season: isMovie ? 1 : seasonNumber,
            episode: isMovie ? 1 : episodeNumber,
            tmdbId: tmdbId.toString(),
          );

          final addonList = (tmdbStreams['streams'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .toList();

          for (final s in addonList) {
            final streamUrl = s['url']?.toString() ?? '';
            if (streamUrl.isNotEmpty && !seenUrls.contains(streamUrl)) {
              addStream(
                url: streamUrl,
                title: s['title']?.toString() ?? cleanTitle,
                provider: s['provider']?.toString() ?? 'Stream Mirror',
                quality: s['quality']?.toString() ?? 'HD',
                addonId: s['addon_id']?.toString() ?? 'builtin.tmdb',
                isDirectLink: s['is_direct_link'] == true,
                headers: s['headers'] is Map ? Map<String, String>.from(s['headers'] as Map) : null,
                subtitles: subtitleTracks,
              );
            }
          }
        } catch (_) {}
      }
    }

    // -------------------------------------------------------------
    // 3. Fallback Mirrors
    // -------------------------------------------------------------
    if (malId > 0) {
      if (isExtEnabled('vidsrc_anime') && (tmdbId == null || streams.isEmpty)) {
        addStream(
          url: 'https://vidsrc.cc/v2/embed/anime/$malId/$episodeNumber',
          title: 'VidSrc Anime (Multi-Server)',
          provider: 'VidSrc Anime',
          quality: '1080p',
          addonId: 'builtin.anime.vidsrc',
          isDirectLink: false,
          subtitles: subtitleTracks,
        );
      }

      if (isExtEnabled('twoembed_anime') && (tmdbId == null || streams.isEmpty)) {
        addStream(
          url: 'https://www.2embed.cc/embed/tv?id=$malId&s=$seasonNumber&e=$episodeNumber',
          title: '2Embed Anime (Fast)',
          provider: '2Embed Anime',
          quality: '1080p',
          addonId: 'builtin.anime.twoembed',
          isDirectLink: false,
          subtitles: subtitleTracks,
        );
      }

      if (isExtEnabled('multiembed_anime') && (tmdbId == null || streams.isEmpty)) {
        addStream(
          url: 'https://multiembed.mov/?video_id=$malId&anime=1&s=$seasonNumber&e=$episodeNumber',
          title: 'MultiEmbed Anime',
          provider: 'MultiEmbed',
          quality: 'HD',
          addonId: 'builtin.anime.multiembed',
          isDirectLink: false,
          subtitles: subtitleTracks,
        );
      }
    }

    return streams;
  }

  // -------------------------------------------------------------
  // OpenAnime Resolver Implementation
  // -------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _resolveOpenAnimeSources({
    required AnimeItem anime,
    required int episodeNumber,
    required int seasonNumber,
  }) async {
    final candidateSlugs = <String>[];

    void addCandidate(String? title) {
      if (title == null || title.trim().isEmpty) return;
      final slug = _slugify(title);
      if (slug.isNotEmpty && !candidateSlugs.contains(slug)) {
        candidateSlugs.add(slug);
      }
      final stripped = _stripDecorations(title);
      if (stripped.isNotEmpty) {
        final strippedSlug = _slugify(stripped);
        if (strippedSlug.isNotEmpty && !candidateSlugs.contains(strippedSlug)) {
          candidateSlugs.add(strippedSlug);
        }
      }
    }

    // Check cached slug first
    if (_slugCache.containsKey(anime.malId)) {
      candidateSlugs.insert(0, _slugCache[anime.malId]!);
    }

    addCandidate(anime.romajiTitle);
    addCandidate(anime.title);
    addCandidate(anime.englishTitle);
    for (final syn in anime.synonyms) {
      addCandidate(syn);
    }

    // Probe candidate slugs
    for (final slug in candidateSlugs.take(4)) {
      final sources = await _probeOpenAnimeSlug(
        slug: slug,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      );
      if (sources.isNotEmpty) {
        _slugCache[anime.malId] = slug;
        return sources;
      }
    }

    // Fallback: Query OpenAnime Vanguard Search API
    final searchTitle = anime.englishTitle?.isNotEmpty == true
        ? anime.englishTitle!
        : anime.title;

    try {
      final searchRes = await _dio.get(
        'https://api.openani.me/anime/search',
        queryParameters: {'q': searchTitle},
        options: Options(
          headers: {
            'Client-Protocol-Model': 'RCSA-14402/05',
          },
        ),
      );

      if (searchRes.statusCode == 200 && searchRes.data is List) {
        final searchList = searchRes.data as List;
        for (final item in searchList.take(3)) {
          if (item is Map && item['slug'] is String) {
            final searchedSlug = item['slug'] as String;
            if (!candidateSlugs.contains(searchedSlug)) {
              final sources = await _probeOpenAnimeSlug(
                slug: searchedSlug,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
              );
              if (sources.isNotEmpty) {
                _slugCache[anime.malId] = searchedSlug;
                return sources;
              }
            }
          }
        }
      }
    } catch (_) {}

    return const [];
  }

  Future<List<Map<String, dynamic>>> _probeOpenAnimeSlug({
    required String slug,
    required int seasonNumber,
    required int episodeNumber,
  }) async {
    final url = 'https://openani.me/anime/$slug/$seasonNumber/$episodeNumber/__data.json';
    try {
      final res = await _dio.get(url);
      if (res.statusCode != 200 || res.data is! Map) return const [];

      final data = res.data as Map;
      final nodes = data['nodes'] as List<dynamic>?;
      if (nodes == null || nodes.isEmpty) return const [];

      // Check if last node indicates an error
      final lastNode = nodes.last;
      if (lastNode is Map && lastNode['type'] == 'error') {
        return const [];
      }

      String? cdnHost;
      final mp4Files = <String>[];

      for (final node in nodes) {
        if (node is! Map || node['data'] is! List) continue;
        final list = node['data'] as List;
        for (final item in list) {
          if (item is String) {
            if (item.startsWith('http') && item.contains('/animes/')) {
              cdnHost = item;
            } else if (item.endsWith('.mp4') || item.contains('.mp4?')) {
              if (!mp4Files.contains(item)) {
                mp4Files.add(item);
              }
            }
          }
        }
      }

      if (cdnHost == null || mp4Files.isEmpty) return const [];

      final base = cdnHost.endsWith('/') ? cdnHost : '$cdnHost/';
      final results = <Map<String, dynamic>>[];

      // Sort files: 1080p first, then 720p, etc.
      mp4Files.sort((a, b) {
        final a1080 = a.contains('1080p') ? 1 : 0;
        final b1080 = b.contains('1080p') ? 1 : 0;
        return b1080.compareTo(a1080);
      });

      for (final file in mp4Files) {
        final cleanFile = file.startsWith('/') ? file.substring(1) : file;
        final videoUrl = '$base$slug/$seasonNumber/$cleanFile';

        String quality = 'HD';
        if (file.contains('1080p')) {
          quality = '1080p';
        } else if (file.contains('720p')) {
          quality = '720p';
        } else if (file.contains('480p')) {
          quality = '480p';
        }

        results.add({
          'url': videoUrl,
          'title': 'OpenAnime $quality (Direct MP4)',
          'quality': quality,
        });
      }

      return results;
    } catch (_) {
      return const [];
    }
  }

  // -------------------------------------------------------------
  // Altyazı Arşivi Subtitle Resolver
  // -------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _resolveAltyaziArsiviSubtitles(
    AnimeItem anime,
    int episodeNumber,
  ) async {
    int? anilistId = anime.anilistId ?? _anilistIdCache[anime.malId];

    if (anilistId == null && anime.malId > 0) {
      try {
        final res = await _dio.post(
          'https://graphql.anilist.co',
          data: {
            'query': '''
              query (\$malId: Int) {
                Media(idMal: \$malId, type: ANIME) {
                  id
                }
              }
            ''',
            'variables': {'malId': anime.malId},
          },
          options: Options(
            headers: {'Content-Type': 'application/json'},
          ),
        );

        if (res.statusCode == 200 && res.data is Map) {
          final data = res.data as Map;
          final media = data['data']?['Media'] as Map<String, dynamic>?;
          if (media?['id'] is int) {
            anilistId = media!['id'] as int;
            _anilistIdCache[anime.malId] = anilistId;
          }
        }
      } catch (_) {}
    }

    if (anilistId == null || anilistId <= 0) return const [];

    final epStr = episodeNumber < 10 ? '0$episodeNumber' : '$episodeNumber';
    final trUrl = 'https://gitlab.com/agnogad/altyazi_arsivi/-/raw/main/subs_api/$anilistId/S01E$epStr.tr.vtt';
    final enUrl = 'https://gitlab.com/agnogad/altyazi_arsivi/-/raw/main/subs_api/$anilistId/S01E$epStr.en.vtt';

    return [
      {
        'url': trUrl,
        'language': 'tr',
        'label': 'Türkçe (Altyazı Arşivi)',
        'format': 'vtt',
      },
      {
        'url': enUrl,
        'language': 'en',
        'label': 'English (Altyazı Arşivi)',
        'format': 'vtt',
      },
    ];
  }

  // -------------------------------------------------------------
  // TMDB ID Resolution
  // -------------------------------------------------------------

  Future<int?> _resolveTmdbId(AnimeItem anime) async {
    if (_tmdbIdCache.containsKey(anime.malId)) {
      return _tmdbIdCache[anime.malId];
    }

    final queryCandidates = <String>[];
    if (anime.englishTitle != null && anime.englishTitle!.trim().isNotEmpty) {
      queryCandidates.add(anime.englishTitle!.trim());
    }
    if (anime.title.trim().isNotEmpty && !queryCandidates.contains(anime.title.trim())) {
      queryCandidates.add(anime.title.trim());
    }
    if (anime.romajiTitle != null &&
        anime.romajiTitle!.trim().isNotEmpty &&
        !queryCandidates.contains(anime.romajiTitle!.trim())) {
      queryCandidates.add(anime.romajiTitle!.trim());
    }

    final endpoint = anime.isMovie
        ? 'https://api.themoviedb.org/3/search/movie'
        : 'https://api.themoviedb.org/3/search/tv';
    final yearParam = anime.isMovie ? 'primary_release_year' : 'first_air_date_year';

    for (final q in queryCandidates) {
      try {
        final res = await _dio.get(
          endpoint,
          queryParameters: {
            'query': q,
            if (anime.year != null && anime.year! > 0) yearParam: anime.year,
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
            final id = results.first['id'] as int;
            _tmdbIdCache[anime.malId] = id;
            return id;
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

  String _stripDecorations(String text) {
    return text
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .trim();
  }
}
