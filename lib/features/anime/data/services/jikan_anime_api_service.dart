import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/anime_item.dart';
import '../../domain/models/anime_episode.dart';

class JikanAnimeApiService {
  static final JikanAnimeApiService _instance = JikanAnimeApiService._internal();
  factory JikanAnimeApiService() => _instance;

  final Dio _dio;
  static const String jikanBaseUrl = 'https://api.jikan.moe/v4';
  static const String anilistUrl = 'https://graphql.anilist.co';

  // Rate Limiting Queue
  DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minInterval = Duration(milliseconds: 350);

  // In-Memory Cache
  final Map<String, ({DateTime timestamp, dynamic data})> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 15);

  JikanAnimeApiService._internal()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 6),
            receiveTimeout: const Duration(seconds: 8),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
              'Accept': 'application/json',
            },
          ),
        );

  Future<void> _throttle() async {
    final now = DateTime.now();
    final elapsed = now.difference(_lastRequestTime);
    if (elapsed < _minInterval) {
      await Future.delayed(_minInterval - elapsed);
    }
    _lastRequestTime = DateTime.now();
  }

  T? _getFromCache<T>(String key) {
    final cached = _cache[key];
    if (cached != null) {
      if (DateTime.now().difference(cached.timestamp) < _cacheDuration) {
        return cached.data as T;
      }
      _cache.remove(key);
    }
    return null;
  }

  void _putInCache(String key, dynamic data) {
    if (_cache.length > 200) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = (timestamp: DateTime.now(), data: data);
  }

  // -------------------------------------------------------------
  // Top / Discovery Categories
  // -------------------------------------------------------------

  /// Top Airing, Popular, Favorite, Upcoming, or Top Rated anime
  Future<List<AnimeItem>> getTopAnime({
    String? filter, // 'airing', 'bypopularity', 'favorite', 'upcoming', or null for top rated
    int page = 1,
    int limit = 20,
  }) async {
    final cacheKey = 'top_${filter ?? "all"}_p${page}_l$limit';
    final cached = _getFromCache<List<AnimeItem>>(cacheKey);
    if (cached != null) return cached;

    try {
      await _throttle();
      final queryParams = <String, dynamic>{
        'page': page,
        'limit': limit,
      };
      if (filter != null && filter.isNotEmpty) {
        queryParams['filter'] = filter;
      }

      final res = await _dio.get(
        '$jikanBaseUrl/top/anime',
        queryParameters: queryParams,
      );

      if (res.statusCode == 200 && res.data is Map && res.data['data'] is List) {
        final list = (res.data['data'] as List)
            .whereType<Map<String, dynamic>>()
            .map((item) => AnimeItem.fromJikan(item))
            .toList();
        _putInCache(cacheKey, list);
        return list;
      }
    } catch (e) {
      debugPrint('[Jikan] getTopAnime ($filter) fallback to AniList: $e');
    }

    // Fallback: AniList GraphQL
    final fallbackList = await _fetchAniListTop(filter: filter, page: page, perPage: limit);
    if (fallbackList.isNotEmpty) {
      _putInCache(cacheKey, fallbackList);
    }
    return fallbackList;
  }

  /// Current Season anime
  Future<List<AnimeItem>> getSeasonNow({int page = 1, int limit = 20}) async {
    final cacheKey = 'season_now_p${page}_l$limit';
    final cached = _getFromCache<List<AnimeItem>>(cacheKey);
    if (cached != null) return cached;

    try {
      await _throttle();
      final res = await _dio.get(
        '$jikanBaseUrl/seasons/now',
        queryParameters: {'page': page, 'limit': limit},
      );

      if (res.statusCode == 200 && res.data is Map && res.data['data'] is List) {
        final list = (res.data['data'] as List)
            .whereType<Map<String, dynamic>>()
            .map((item) => AnimeItem.fromJikan(item))
            .toList();
        _putInCache(cacheKey, list);
        return list;
      }
    } catch (e) {
      debugPrint('[Jikan] getSeasonNow fallback to AniList: $e');
    }

    final fallbackList = await _fetchAniListSeasonNow(page: page, perPage: limit);
    if (fallbackList.isNotEmpty) {
      _putInCache(cacheKey, fallbackList);
    }
    return fallbackList;
  }

  /// Recently Updated anime
  Future<List<AnimeItem>> getRecentlyUpdated({int page = 1, int limit = 20}) async {
    final cacheKey = 'recently_updated_p${page}_l$limit';
    final cached = _getFromCache<List<AnimeItem>>(cacheKey);
    if (cached != null) return cached;

    try {
      await _throttle();
      final res = await _dio.get(
        '$jikanBaseUrl/anime',
        queryParameters: {
          'page': page,
          'limit': limit,
          'order_by': 'updated',
          'sort': 'desc',
        },
      );

      if (res.statusCode == 200 && res.data is Map && res.data['data'] is List) {
        final list = (res.data['data'] as List)
            .whereType<Map<String, dynamic>>()
            .map((item) => AnimeItem.fromJikan(item))
            .toList();
        _putInCache(cacheKey, list);
        return list;
      }
    } catch (e) {
      debugPrint('[Jikan] getRecentlyUpdated fallback to AniList: $e');
    }

    final fallbackList = await _fetchAniListRecentlyUpdated(page: page, perPage: limit);
    if (fallbackList.isNotEmpty) {
      _putInCache(cacheKey, fallbackList);
    }
    return fallbackList;
  }

  /// Top Anime Movies
  Future<List<AnimeItem>> getTopMovies({int page = 1, int limit = 20}) async {
    final cacheKey = 'top_movies_p${page}_l$limit';
    final cached = _getFromCache<List<AnimeItem>>(cacheKey);
    if (cached != null) return cached;

    // Fast-path: AniList Movies (Instant, high-res banners, real movie ratings)
    final gql = '''
      query {
        Page(page: $page, perPage: $limit) {
          media(type: ANIME, format: MOVIE, sort: [POPULARITY_DESC]) {
            id
            idMal
            title { english romaji native }
            coverImage { extraLarge large medium }
            bannerImage
            description
            format
            episodes
            status
            averageScore
            genres
            seasonYear
            season
            duration
            synonyms
          }
        }
      }
    ''';

    final aniListMovies = await _postAniListQuery(gql);
    if (aniListMovies.isNotEmpty) {
      _putInCache(cacheKey, aniListMovies);
      return aniListMovies;
    }

    // Fallback: Jikan anime with type=movie
    try {
      await _throttle();
      final res = await _dio.get(
        '$jikanBaseUrl/anime',
        queryParameters: {
          'type': 'movie',
          'order_by': 'popularity',
          'sort': 'asc',
          'page': page,
          'limit': limit,
        },
      );
      if (res.statusCode == 200 && res.data is Map && res.data['data'] is List) {
        final list = (res.data['data'] as List)
            .whereType<Map<String, dynamic>>()
            .map((item) => AnimeItem.fromJikan(item))
            .toList();
        if (list.isNotEmpty) {
          _putInCache(cacheKey, list);
          return list;
        }
      }
    } catch (_) {}

    return [];
  }

  // -------------------------------------------------------------
  // Anime Details & Episodes
  // -------------------------------------------------------------

  Future<AnimeItem?> getAnimeDetails(int malId) async {
    final cacheKey = 'details_$malId';
    final cached = _getFromCache<AnimeItem>(cacheKey);
    if (cached != null) return cached;

    // 1. Fast-path: AniList GraphQL (<180ms, full title, horizontal banner, format, episodes)
    final aniItem = await _fetchAniListDetails(malId);
    if (aniItem != null) {
      _putInCache(cacheKey, aniItem);
      return aniItem;
    }

    // 2. Fallback: Jikan
    try {
      await _throttle();
      final res = await _dio.get(
        '$jikanBaseUrl/anime/$malId/full',
        options: Options(
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );
      if (res.statusCode == 200 && res.data is Map && res.data['data'] is Map) {
        final item = AnimeItem.fromJikan(res.data['data'] as Map<String, dynamic>);
        _putInCache(cacheKey, item);
        return item;
      }
    } catch (e) {
      debugPrint('[Jikan] getAnimeDetails($malId) error: $e');
    }

    return null;
  }

  Future<List<AnimeEpisode>> getAnimeEpisodes(
    int malId, {
    int page = 1,
    int? totalCount,
    String? title,
    String? defaultThumbnail,
  }) async {
    final cacheKey = 'episodes_${malId}_p$page';
    final cached = _getFromCache<List<AnimeEpisode>>(cacheKey);
    if (cached != null) return cached;

    // 1. Fast Kitsu lookup if title is given (returns real thumbnails & synopses)
    if (title != null && title.trim().isNotEmpty) {
      try {
        final kitsuList = await _fetchKitsuEpisodes(malId, title.trim());
        if (kitsuList.isNotEmpty) {
          _putInCache(cacheKey, kitsuList);
          return kitsuList;
        }
      } catch (_) {}
    }

    // 2. Jikan fallback with short timeout
    try {
      final res = await _dio.get(
        '$jikanBaseUrl/anime/$malId/episodes',
        queryParameters: {'page': page},
        options: Options(
          receiveTimeout: const Duration(seconds: 3),
          sendTimeout: const Duration(seconds: 3),
        ),
      );

      if (res.statusCode == 200 && res.data is Map && res.data['data'] is List) {
        final list = (res.data['data'] as List)
            .whereType<Map<String, dynamic>>()
            .map((entry) => AnimeEpisode.fromJikan(malId, entry))
            .toList();
        if (list.isNotEmpty) {
          _putInCache(cacheKey, list);
          return list;
        }
      }
    } catch (e) {
      debugPrint('[Jikan] getAnimeEpisodes($malId) fallback: $e');
    }

    // 3. Fallback to synthetic with known count (or 12)
    final count = (totalCount != null && totalCount > 0) ? totalCount : 12;
    final syntheticList = List.generate(
      count,
      (index) => AnimeEpisode.synthetic(
        malId,
        index + 1,
        defaultThumbnail: defaultThumbnail,
      ),
    );
    _putInCache(cacheKey, syntheticList);
    return syntheticList;
  }

  // -------------------------------------------------------------
  // Search & Genres
  // -------------------------------------------------------------

  Future<List<AnimeItem>> searchAnime({
    required String query,
    String? type,
    String? status,
    String? genres,
    String? orderBy,
    String? sort,
    int page = 1,
    int limit = 20,
  }) async {
    final cacheKey = 'search_${query}_${type}_${genres}_p$page';
    final cached = _getFromCache<List<AnimeItem>>(cacheKey);
    if (cached != null) return cached;

    // Fast-path: AniList GraphQL responds in <250ms, has no rate limit, and returns real MAL IDs + Romaji/English/Synonyms
    final aniListResults = await _fetchAniListSearch(
      query: query,
      genre: genres,
      format: type,
      page: page,
      perPage: limit,
    );
    if (aniListResults.isNotEmpty) {
      _putInCache(cacheKey, aniListResults);
      return aniListResults;
    }

    try {
      await _throttle();
      final queryParams = <String, dynamic>{
        'q': query,
        'page': page,
        'limit': limit,
      };
      if (type != null && type.isNotEmpty) queryParams['type'] = type;
      if (status != null && status.isNotEmpty) queryParams['status'] = status;
      if (genres != null && genres.isNotEmpty) queryParams['genres'] = genres;
      if (orderBy != null && orderBy.isNotEmpty) {
        queryParams['order_by'] = orderBy;
        queryParams['sort'] = sort ?? 'desc';
      }

      final res = await _dio.get(
        '$jikanBaseUrl/anime',
        queryParameters: queryParams,
      );

      if (res.statusCode == 200 && res.data is Map && res.data['data'] is List) {
        final list = (res.data['data'] as List)
            .whereType<Map<String, dynamic>>()
            .map((item) => AnimeItem.fromJikan(item))
            .toList();
        if (list.isNotEmpty) {
          _putInCache(cacheKey, list);
          return list;
        }
      }
    } catch (e) {
      debugPrint('[Jikan] searchAnime ($query) fallback error: $e');
    }

    return const [];
  }

  Future<List<String>> getGenres() async {
    const cacheKey = 'genres_list';
    final cached = _getFromCache<List<String>>(cacheKey);
    if (cached != null) return cached;

    try {
      await _throttle();
      final res = await _dio.get('$jikanBaseUrl/genres/anime');
      if (res.statusCode == 200 && res.data is Map && res.data['data'] is List) {
        final genres = (res.data['data'] as List)
            .whereType<Map<String, dynamic>>()
            .map((g) => g['name']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .toList();
        if (genres.isNotEmpty) {
          _putInCache(cacheKey, genres);
          return genres;
        }
      }
    } catch (_) {}

    // Static popular genres
    final staticGenres = [
      'Action',
      'Adventure',
      'Comedy',
      'Drama',
      'Fantasy',
      'Horror',
      'Mystery',
      'Romance',
      'Sci-Fi',
      'Slice of Life',
      'Sports',
      'Supernatural',
      'Suspense',
    ];
    _putInCache(cacheKey, staticGenres);
    return staticGenres;
  }

  // -------------------------------------------------------------
  // Recommendations & Characters
  // -------------------------------------------------------------

  Future<List<AnimeItem>> getAnimeRecommendations(int malId) async {
    final cacheKey = 'recs_$malId';
    final cached = _getFromCache<List<AnimeItem>>(cacheKey);
    if (cached != null) return cached;

    // 1. Fast AniList GraphQL
    final aniListRecs = await _fetchAniListRecommendations(malId);
    if (aniListRecs.isNotEmpty) {
      _putInCache(cacheKey, aniListRecs);
      return aniListRecs;
    }

    // 2. Jikan fallback
    try {
      await _throttle();
      final res = await _dio.get('$jikanBaseUrl/anime/$malId/recommendations');
      if (res.statusCode == 200 && res.data is Map && res.data['data'] is List) {
        final list = <AnimeItem>[];
        for (final item in res.data['data']) {
          if (item is Map && item['entry'] is Map) {
            final entry = item['entry'] as Map<String, dynamic>;
            list.add(AnimeItem.fromJikan(entry));
          }
        }
        if (list.isNotEmpty) {
          _putInCache(cacheKey, list);
          return list;
        }
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, dynamic>>> getAnimeCharacters(int malId) async {
    final cacheKey = 'chars_$malId';
    final cached = _getFromCache<List<Map<String, dynamic>>>(cacheKey);
    if (cached != null) return cached;

    // 1. Fast AniList GraphQL
    final aniListChars = await _fetchAniListCharacters(malId);
    if (aniListChars.isNotEmpty) {
      _putInCache(cacheKey, aniListChars);
      return aniListChars;
    }

    // 2. Jikan fallback
    try {
      await _throttle();
      final res = await _dio.get('$jikanBaseUrl/anime/$malId/characters');
      if (res.statusCode == 200 && res.data is Map && res.data['data'] is List) {
        final list = <Map<String, dynamic>>[];
        for (final entry in res.data['data']) {
          if (entry is! Map) continue;
          final charObj = entry['character'] as Map<String, dynamic>?;
          final voiceActors = entry['voice_actors'] as List?;
          Map<String, dynamic>? actorObj;
          if (voiceActors != null && voiceActors.isNotEmpty) {
            for (final va in voiceActors) {
              if (va is Map && va['language'] == 'Japanese') {
                actorObj = va['person'] as Map<String, dynamic>?;
                break;
              }
            }
            if (actorObj == null && voiceActors.first is Map) {
              actorObj = voiceActors.first['person'] as Map<String, dynamic>?;
            }
          }

          list.add({
            'name': charObj?['name']?.toString() ?? 'Character',
            'role': entry['role']?.toString() ?? '',
            'image': charObj?['images']?['jpg']?['image_url']?.toString(),
            'actor_name': actorObj?['name']?.toString(),
            'actor_image': actorObj?['images']?['jpg']?['image_url']?.toString(),
          });
        }
        if (list.isNotEmpty) {
          _putInCache(cacheKey, list);
          return list;
        }
      }
    } catch (_) {}
    return [];
  }

  // =============================================================
  // AniList Fallback Implementation (Identical to pixiAndroid)
  // =============================================================

  Future<List<AnimeItem>> _fetchAniListTop({
    String? filter,
    int page = 1,
    int perPage = 20,
  }) async {
    String sortParam = 'SCORE_DESC';
    String? statusParam;

    if (filter == 'airing') {
      statusParam = 'status: RELEASING, ';
      sortParam = 'SCORE_DESC';
    } else if (filter == 'upcoming') {
      statusParam = 'status: NOT_YET_RELEASED, ';
      sortParam = 'POPULARITY_DESC';
    } else if (filter == 'bypopularity') {
      sortParam = 'POPULARITY_DESC';
    } else if (filter == 'favorite') {
      sortParam = 'FAVOURITES_DESC';
    }

    final query = '''
      query {
        Page(page: $page, perPage: $perPage) {
          media(type: ANIME, ${statusParam ?? ''}sort: [$sortParam]) {
            id
            idMal
            title { english romaji native }
            coverImage { extraLarge large medium }
            bannerImage
            description
            format
            episodes
            status
            averageScore
            genres
            seasonYear
            season
            duration
            synonyms
          }
        }
      }
    ''';

    return _postAniListQuery(query);
  }

  Future<List<AnimeItem>> _fetchAniListSeasonNow({
    int page = 1,
    int perPage = 20,
  }) async {
    final now = DateTime.now();
    final year = now.year;
    final season = _currentSeasonString(now.month);

    final query = '''
      query {
        Page(page: $page, perPage: $perPage) {
          media(type: ANIME, season: $season, seasonYear: $year, sort: [POPULARITY_DESC]) {
            id
            idMal
            title { english romaji native }
            coverImage { extraLarge large medium }
            bannerImage
            description
            format
            episodes
            status
            averageScore
            genres
            seasonYear
            season
            duration
            synonyms
          }
        }
      }
    ''';

    return _postAniListQuery(query);
  }

  Future<List<AnimeItem>> _fetchAniListRecentlyUpdated({
    int page = 1,
    int perPage = 20,
  }) async {
    final query = '''
      query {
        Page(page: $page, perPage: $perPage) {
          media(type: ANIME, sort: [UPDATED_AT_DESC]) {
            id
            idMal
            title { english romaji native }
            coverImage { extraLarge large medium }
            bannerImage
            description
            format
            episodes
            status
            averageScore
            genres
            seasonYear
            season
            duration
            synonyms
          }
        }
      }
    ''';

    return _postAniListQuery(query);
  }

  Future<List<AnimeItem>> _fetchAniListSearch({
    required String query,
    String? genre,
    String? format,
    int page = 1,
    int perPage = 20,
  }) async {
    final escapedQuery = query.replaceAll('"', '\\"');
    final genreFilter = genre != null && genre.isNotEmpty ? 'genre: "$genre", ' : '';
    final searchFilter = query.isNotEmpty ? 'search: "$escapedQuery", ' : '';
    final formatFilter = (format != null && format.isNotEmpty)
        ? 'format: ${format.toUpperCase()}, '
        : '';

    final gql = '''
      query {
        Page(page: $page, perPage: $perPage) {
          media(type: ANIME, $searchFilter$genreFilter$formatFilter sort: [SEARCH_MATCH, POPULARITY_DESC]) {
            id
            idMal
            title { english romaji native }
            coverImage { extraLarge large medium }
            bannerImage
            description
            format
            episodes
            status
            averageScore
            genres
            seasonYear
            season
            duration
            synonyms
          }
        }
      }
    ''';

    return _postAniListQuery(gql);
  }

  Future<AnimeItem?> _fetchAniListDetails(int malId) async {
    final gql = '''
      query {
        Media(idMal: $malId, type: ANIME) {
          id
          idMal
          title { english romaji native }
          coverImage { extraLarge large medium }
          bannerImage
          description
          format
          episodes
          status
          averageScore
          genres
          seasonYear
          season
          duration
          synonyms
          studios(isMain: true) {
            nodes { name }
          }
        }
      }
    ''';

    try {
      final res = await _dio.post(
        anilistUrl,
        data: {'query': gql},
      );
      if (res.statusCode == 200 &&
          res.data is Map &&
          res.data['data'] is Map &&
          res.data['data']['Media'] is Map) {
        return AnimeItem.fromAniList(res.data['data']['Media'] as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[AniList] Details error: $e');
    }
    return null;
  }

  Future<List<AnimeItem>> _postAniListQuery(String query) async {
    try {
      final res = await _dio.post(
        anilistUrl,
        data: {'query': query},
      );

      if (res.statusCode == 200 &&
          res.data is Map &&
          res.data['data'] is Map &&
          res.data['data']['Page'] is Map &&
          res.data['data']['Page']['media'] is List) {
        return (res.data['data']['Page']['media'] as List)
            .whereType<Map<String, dynamic>>()
            .map((item) => AnimeItem.fromAniList(item))
            .toList();
      }
    } catch (e) {
      debugPrint('[AniList] Query error: $e');
    }
    return [];
  }

  Future<List<AnimeEpisode>> _fetchKitsuEpisodes(int malId, String title) async {
    try {
      final searchRes = await _dio.get(
        'https://kitsu.io/api/edge/anime',
        queryParameters: {
          'filter[text]': title,
          'page[limit]': 1,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
        ),
      );
      if (searchRes.statusCode == 200 &&
          searchRes.data is Map &&
          searchRes.data['data'] is List &&
          (searchRes.data['data'] as List).isNotEmpty) {
        final kitsuItem = (searchRes.data['data'] as List).first as Map<String, dynamic>;
        final kitsuId = kitsuItem['id'];
        if (kitsuId != null) {
          final epRes = await _dio.get(
            'https://kitsu.io/api/edge/anime/$kitsuId/episodes',
            queryParameters: {
              'page[limit]': 100,
            },
            options: Options(
              receiveTimeout: const Duration(seconds: 5),
              sendTimeout: const Duration(seconds: 5),
            ),
          );
          if (epRes.statusCode == 200 &&
              epRes.data is Map &&
              epRes.data['data'] is List) {
            final list = (epRes.data['data'] as List)
                .whereType<Map<String, dynamic>>()
                .map((e) => AnimeEpisode.fromKitsu(malId, e))
                .toList();
            if (list.isNotEmpty) {
              return list;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Kitsu] _fetchKitsuEpisodes error: $e');
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> _fetchAniListCharacters(int malId) async {
    final query = '''
      query {
        Media(idMal: $malId, type: ANIME) {
          characters(sort: [ROLE, RELEVANCE], perPage: 25) {
            edges {
              role
              node {
                name { full }
                image { large medium }
              }
              voiceActors(language: JAPANESE) {
                name { full }
                image { large medium }
              }
            }
          }
        }
      }
    ''';
    try {
      final res = await _dio.post(
        anilistUrl,
        data: {'query': query},
      );
      if (res.statusCode == 200 &&
          res.data is Map &&
          res.data['data'] is Map &&
          res.data['data']['Media'] is Map) {
        final media = res.data['data']['Media'] as Map<String, dynamic>;
        final chars = media['characters'] as Map<String, dynamic>?;
        final edges = chars?['edges'] as List?;
        if (edges != null && edges.isNotEmpty) {
          final list = <Map<String, dynamic>>[];
          for (final edge in edges) {
            if (edge is! Map) continue;
            final node = edge['node'] as Map<String, dynamic>?;
            final nameObj = node?['name'] as Map<String, dynamic>?;
            final imgObj = node?['image'] as Map<String, dynamic>?;
            final vaList = edge['voiceActors'] as List?;
            Map<String, dynamic>? vaNode;
            if (vaList != null && vaList.isNotEmpty && vaList.first is Map) {
              vaNode = vaList.first as Map<String, dynamic>;
            }
            final vaNameObj = vaNode?['name'] as Map<String, dynamic>?;
            final vaImgObj = vaNode?['image'] as Map<String, dynamic>?;

            list.add({
              'name': nameObj?['full']?.toString() ?? 'Character',
              'role': edge['role']?.toString() ?? '',
              'image': imgObj?['large']?.toString() ?? imgObj?['medium']?.toString(),
              'actor_name': vaNameObj?['full']?.toString(),
              'actor_image': vaImgObj?['large']?.toString() ?? vaImgObj?['medium']?.toString(),
            });
          }
          return list;
        }
      }
    } catch (e) {
      debugPrint('[AniList] characters error: $e');
    }
    return [];
  }

  Future<List<AnimeItem>> _fetchAniListRecommendations(int malId) async {
    final query = '''
      query {
        Media(idMal: $malId, type: ANIME) {
          recommendations(sort: [RATING_DESC], perPage: 15) {
            nodes {
              mediaRecommendation {
                id
                idMal
                title { english romaji native }
                coverImage { extraLarge large medium }
                bannerImage
                description
                format
                episodes
                averageScore
                genres
                duration
              }
            }
          }
        }
      }
    ''';
    try {
      final res = await _dio.post(
        anilistUrl,
        data: {'query': query},
      );
      if (res.statusCode == 200 &&
          res.data is Map &&
          res.data['data'] is Map &&
          res.data['data']['Media'] is Map) {
        final media = res.data['data']['Media'] as Map<String, dynamic>;
        final recs = media['recommendations'] as Map<String, dynamic>?;
        final nodes = recs?['nodes'] as List?;
        if (nodes != null && nodes.isNotEmpty) {
          final list = <AnimeItem>[];
          for (final node in nodes) {
            if (node is! Map) continue;
            final mr = node['mediaRecommendation'] as Map<String, dynamic>?;
            if (mr != null) {
              list.add(AnimeItem.fromAniList(mr));
            }
          }
          return list;
        }
      }
    } catch (e) {
      debugPrint('[AniList] recommendations error: $e');
    }
    return [];
  }

  String _currentSeasonString(int month) {
    if (month >= 1 && month <= 3) return 'WINTER';
    if (month >= 4 && month <= 6) return 'SPRING';
    if (month >= 7 && month <= 9) return 'SUMMER';
    return 'FALL';
  }
}
