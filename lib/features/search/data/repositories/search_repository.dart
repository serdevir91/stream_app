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
