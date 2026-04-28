import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import '../../domain/entities/media_item.dart';

class SearchRepository {
  final Dio _dio;
  final String _tmdbAccessToken;
  final String _tmdbLanguage;

  SearchRepository(
    this._dio, {
    required String tmdbAccessToken,
    required String tmdbLanguage,
  }) : _tmdbAccessToken = tmdbAccessToken,
       _tmdbLanguage = tmdbLanguage;

  bool get _hasToken => _tmdbAccessToken.trim().isNotEmpty;

  Options get _tmdbOptions => Options(
    headers: {
      'Authorization': 'Bearer ${_tmdbAccessToken.trim()}',
      'Accept': 'application/json',
    },
  );

  Future<List<MediaItem>> search(String query) async {
    if (!_hasToken) return [];
    try {
      final response = await _dio.get(
        'https://api.themoviedb.org/3/search/multi',
        queryParameters: {'query': query, 'language': _tmdbLanguage, 'page': 1},
        options: _tmdbOptions,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['results'] != null) {
          final List<dynamic> items = data['results'];
          return items
              .where(
                (json) =>
                    json['media_type'] == 'movie' || json['media_type'] == 'tv',
              )
              .map((json) => MediaItem.fromTmdbJson(json))
              .toList();
        }
      }
    } catch (e) {
      developer.log('Error searching TMDB: $e', name: 'SearchRepository');
    }
    return [];
  }

  Future<List<MediaItem>> getTrendingMovies() async {
    if (!_hasToken) return [];
    try {
      final response = await _dio.get(
        'https://api.themoviedb.org/3/trending/movie/day',
        queryParameters: {'language': _tmdbLanguage},
        options: _tmdbOptions,
      );
      if (response.statusCode == 200) {
        return (response.data['results'] as List)
            .map(
              (json) =>
                  MediaItem.fromTmdbJson({...json, 'media_type': 'movie'}),
            )
            .toList();
      }
    } catch (e) {
      developer.log(
        'Trending movies fetch failed: $e',
        name: 'SearchRepository',
      );
    }
    return [];
  }

  Future<List<MediaItem>> getTrendingSeries() async {
    if (!_hasToken) return [];
    try {
      final response = await _dio.get(
        'https://api.themoviedb.org/3/trending/tv/day',
        queryParameters: {'language': _tmdbLanguage},
        options: _tmdbOptions,
      );
      if (response.statusCode == 200) {
        return (response.data['results'] as List)
            .map(
              (json) => MediaItem.fromTmdbJson({...json, 'media_type': 'tv'}),
            )
            .toList();
      }
    } catch (e) {
      developer.log(
        'Trending series fetch failed: $e',
        name: 'SearchRepository',
      );
    }
    return [];
  }

  Future<List<Season>> getSeriesSeasons(String seriesId) async {
    if (!_hasToken) return [];
    try {
      final response = await _dio.get(
        'https://api.themoviedb.org/3/tv/$seriesId',
        queryParameters: {'language': _tmdbLanguage},
        options: _tmdbOptions,
      );
      if (response.statusCode == 200) {
        final List<dynamic> seasons = response.data['seasons'];
        return seasons
            .map((json) => Season.fromTmdbJson(json))
            .where((s) => s.seasonNumber > 0)
            .toList();
      }
    } catch (e) {
      developer.log(
        'Series seasons fetch failed: $e',
        name: 'SearchRepository',
      );
    }
    return [];
  }

  Future<List<Episode>> getSeasonEpisodes(
    String seriesId,
    int seasonNumber,
  ) async {
    if (!_hasToken) return [];
    try {
      final response = await _dio.get(
        'https://api.themoviedb.org/3/tv/$seriesId/season/$seasonNumber',
        queryParameters: {'language': _tmdbLanguage},
        options: _tmdbOptions,
      );
      if (response.statusCode == 200) {
        final List<dynamic> episodes = response.data['episodes'];
        return episodes.map((json) => Episode.fromTmdbJson(json)).toList();
      }
    } catch (e) {
      developer.log(
        'Season episodes fetch failed: $e',
        name: 'SearchRepository',
      );
    }
    return [];
  }

  Future<List<MediaItem>> getMoviesByGenre(int genreId) async {
    if (!_hasToken) return [];
    try {
      final response = await _dio.get(
        'https://api.themoviedb.org/3/discover/movie',
        queryParameters: {'language': _tmdbLanguage, 'with_genres': genreId},
        options: _tmdbOptions,
      );
      if (response.statusCode == 200) {
        return (response.data['results'] as List)
            .map(
              (json) =>
                  MediaItem.fromTmdbJson({...json, 'media_type': 'movie'}),
            )
            .toList();
      }
    } catch (e) {
      developer.log(
        'Movies by genre fetch failed: $e',
        name: 'SearchRepository',
      );
    }
    return [];
  }

  Future<List<MediaItem>> getSeriesByGenre(int genreId) async {
    if (!_hasToken) return [];
    try {
      final response = await _dio.get(
        'https://api.themoviedb.org/3/discover/tv',
        queryParameters: {'language': _tmdbLanguage, 'with_genres': genreId},
        options: _tmdbOptions,
      );
      if (response.statusCode == 200) {
        return (response.data['results'] as List)
            .map(
              (json) => MediaItem.fromTmdbJson({...json, 'media_type': 'tv'}),
            )
            .toList();
      }
    } catch (e) {
      developer.log(
        'Series by genre fetch failed: $e',
        name: 'SearchRepository',
      );
    }
    return [];
  }

  Future<List<MediaItem>> getFeaturedWeeklyHighRated() async {
    if (!_hasToken) return [];
    try {
      final weekly = await _dio.get(
        'https://api.themoviedb.org/3/trending/all/week',
        queryParameters: {'language': _tmdbLanguage},
        options: _tmdbOptions,
      );

      final weeklyItems = (weekly.data['results'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((json) => Map<String, dynamic>.from(json))
          .where((json) {
            final mediaType = (json['media_type'] ?? '').toString();
            return mediaType == 'movie' || mediaType == 'tv';
          })
          .map((json) => MediaItem.fromTmdbJson(json))
          .where((item) => (item.rating ?? 0) >= 7.0)
          .toList();

      weeklyItems.sort((a, b) {
        final aRating = a.rating ?? 0;
        final bRating = b.rating ?? 0;
        return bRating.compareTo(aRating);
      });

      if (weeklyItems.length >= 10) {
        return weeklyItems.take(12).toList();
      }

      final responses = await Future.wait([
        _dio.get(
          'https://api.themoviedb.org/3/discover/movie',
          queryParameters: {
            'language': _tmdbLanguage,
            'sort_by': 'primary_release_date.desc',
            'vote_average.gte': 7.0,
            'vote_count.gte': 120,
            'include_adult': false,
            'page': 1,
          },
          options: _tmdbOptions,
        ),
        _dio.get(
          'https://api.themoviedb.org/3/discover/tv',
          queryParameters: {
            'language': _tmdbLanguage,
            'sort_by': 'first_air_date.desc',
            'vote_average.gte': 7.0,
            'vote_count.gte': 80,
            'include_adult': false,
            'page': 1,
          },
          options: _tmdbOptions,
        ),
      ]);

      final movies = (responses[0].data['results'] as List<dynamic>? ?? const [])
          .map((json) => MediaItem.fromTmdbJson({...json, 'media_type': 'movie'}))
          .toList();
      final series = (responses[1].data['results'] as List<dynamic>? ?? const [])
          .map((json) => MediaItem.fromTmdbJson({...json, 'media_type': 'tv'}))
          .toList();

      final merged = [...weeklyItems, ...movies, ...series];
      final seen = <String>{};
      final deduped = <MediaItem>[];
      for (final item in merged) {
        final key = '${item.type}:${item.id}';
        if (seen.add(key)) {
          deduped.add(item);
        }
      }
      deduped.sort((a, b) {
        final aRating = a.rating ?? 0;
        final bRating = b.rating ?? 0;
        return bRating.compareTo(aRating);
      });
      return deduped.take(12).toList();
    } catch (e) {
      developer.log(
        'Featured weekly fetch failed: $e',
        name: 'SearchRepository',
      );
    }
    return [];
  }

  Future<List<MediaItem>> getRecommendedForMedia(
    String mediaId, {
    required String mediaType,
  }) async {
    if (!_hasToken || mediaId.trim().isEmpty) return [];
    final type = mediaType == 'tv' ? 'tv' : 'movie';
    try {
      final response = await _dio.get(
        'https://api.themoviedb.org/3/$type/$mediaId/recommendations',
        queryParameters: {'language': _tmdbLanguage, 'page': 1},
        options: _tmdbOptions,
      );
      if (response.statusCode == 200) {
        return (response.data['results'] as List<dynamic>? ?? const [])
            .map(
              (json) =>
                  MediaItem.fromTmdbJson({...json, 'media_type': type}),
            )
            .toList();
      }
    } catch (e) {
      developer.log(
        'Recommendation fetch failed: $e',
        name: 'SearchRepository',
      );
    }
    return [];
  }

  Future<List<MediaItem>> getClassicMovies() {
    return getMoviesByDecade(fromYear: 1930, toYear: 1999, minVote: 7.2);
  }

  Future<List<MediaItem>> getWesternMovies() {
    return getMoviesByDecade(
      fromYear: 1950,
      toYear: DateTime.now().year,
      genreId: 37,
      minVote: 6.8,
    );
  }

  Future<List<MediaItem>> getMoviesByDecade({
    required int fromYear,
    required int toYear,
    int? genreId,
    double minVote = 6.5,
  }) async {
    if (!_hasToken) return [];
    try {
      final query = <String, dynamic>{
        'language': _tmdbLanguage,
        'primary_release_date.gte': '$fromYear-01-01',
        'primary_release_date.lte': '$toYear-12-31',
        'vote_average.gte': minVote,
        'vote_count.gte': 50,
        'sort_by': 'vote_average.desc',
        'include_adult': false,
        'page': 1,
      };
      if (genreId != null) {
        query['with_genres'] = genreId;
      }

      final response = await _dio.get(
        'https://api.themoviedb.org/3/discover/movie',
        queryParameters: query,
        options: _tmdbOptions,
      );

      if (response.statusCode == 200) {
        return (response.data['results'] as List<dynamic>? ?? const [])
            .map(
              (json) =>
                  MediaItem.fromTmdbJson({...json, 'media_type': 'movie'}),
            )
            .toList();
      }
    } catch (e) {
      developer.log(
        'Movies by decade fetch failed: $e',
        name: 'SearchRepository',
      );
    }
    return [];
  }

  Future<List<MediaItem>> getLatestVidSrcMovies({int page = 1}) async {
    try {
      final response = await _dio.get(
        'https://vidsrc-embed.ru/movies/latest/page-$page.json',
      );
      if (response.statusCode == 200 && response.data['result'] != null) {
        return (response.data['result'] as List)
            .map((json) => MediaItem.fromVidSrcJson(json, 'movie'))
            .toList();
      }
    } catch (e) {
      developer.log(
        'Latest VidSrc movies fetch failed: $e',
        name: 'SearchRepository',
      );
    }
    return [];
  }

  Future<List<MediaItem>> getLatestVidSrcSeries({int page = 1}) async {
    try {
      final response = await _dio.get(
        'https://vidsrc-embed.ru/tvshows/latest/page-$page.json',
      );
      if (response.statusCode == 200 && response.data['result'] != null) {
        return (response.data['result'] as List)
            .map((json) => MediaItem.fromVidSrcJson(json, 'tv'))
            .toList();
      }
    } catch (e) {
      developer.log(
        'Latest VidSrc series fetch failed: $e',
        name: 'SearchRepository',
      );
    }
    return [];
  }
}
