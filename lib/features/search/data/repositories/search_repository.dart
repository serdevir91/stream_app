import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import '../../domain/entities/media_item.dart';

class StudioConfig {
  final String name;
  final String key;
  final List<int> movieCompanyIds;
  final List<int> tvNetworkIds;
  final List<int>? tvCompanyIds;

  const StudioConfig({
    required this.name,
    required this.key,
    required this.movieCompanyIds,
    required this.tvNetworkIds,
    this.tvCompanyIds,
  });
}

const List<StudioConfig> studios = [
  StudioConfig(
    name: 'Marvel',
    key: 'marvel',
    movieCompanyIds: [420],
    tvNetworkIds: [],
    tvCompanyIds: [420],
  ),
  StudioConfig(
    name: 'Disney',
    key: 'disney',
    movieCompanyIds: [2],
    tvNetworkIds: [2739],
    tvCompanyIds: [2],
  ),
  StudioConfig(
    name: 'DreamWorks',
    key: 'dreamworks',
    movieCompanyIds: [521, 6125],
    tvNetworkIds: [],
    tvCompanyIds: [521, 6125],
  ),
  StudioConfig(
    name: 'DC',
    key: 'dc',
    movieCompanyIds: [9993, 128064],
    tvNetworkIds: [],
    tvCompanyIds: [9993, 128064],
  ),
  StudioConfig(
    name: 'Paramount',
    key: 'paramount',
    movieCompanyIds: [4],
    tvNetworkIds: [],
    tvCompanyIds: [4],
  ),
  StudioConfig(
    name: 'Netflix',
    key: 'netflix',
    movieCompanyIds: [178200],
    tvNetworkIds: [213],
  ),
  StudioConfig(
    name: 'HBO',
    key: 'hbo',
    movieCompanyIds: [3268],
    tvNetworkIds: [49],
  ),
  StudioConfig(
    name: 'Prime Video',
    key: 'prime',
    movieCompanyIds: [20580],
    tvNetworkIds: [1024],
  ),
  StudioConfig(
    name: 'Pixar',
    key: 'pixar',
    movieCompanyIds: [3],
    tvNetworkIds: [],
  ),
  StudioConfig(
    name: 'Warner Bros.',
    key: 'warnerbros',
    movieCompanyIds: [174],
    tvNetworkIds: [],
  ),
  StudioConfig(
    name: 'Universal',
    key: 'universal',
    movieCompanyIds: [33],
    tvNetworkIds: [],
  ),
];

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

  int? _extractRuntimeMinutes(Map<String, dynamic> data, String mediaType) {
    if (mediaType == 'movie') {
      final runtime = data['runtime'];
      if (runtime is num && runtime.toInt() > 0) {
        return runtime.toInt();
      }
      return null;
    }

    final runtimes = data['episode_run_time'];
    if (runtimes is List) {
      for (final runtime in runtimes) {
        if (runtime is num && runtime.toInt() > 0) {
          return runtime.toInt();
        }
      }
    }
    return null;
  }

  List<String> _extractCastNames(
    Map<String, dynamic>? credits, {
    int limit = 5,
  }) {
    final cast = credits?['cast'];
    if (cast is! List) {
      return const [];
    }

    return cast
        .whereType<Map>()
        .map((entry) => (entry['name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .take(limit)
        .toList();
  }

  String? _extractCrewName(
    Map<String, dynamic>? credits, {
    required String job,
  }) {
    final crew = credits?['crew'];
    if (crew is! List) {
      return null;
    }

    for (final entry in crew.whereType<Map>()) {
      final entryJob = (entry['job'] ?? '').toString().trim();
      if (entryJob.toLowerCase() == job.toLowerCase()) {
        final name = (entry['name'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          return name;
        }
      }
    }
    return null;
  }

  String? _extractCreatorName(Map<String, dynamic> data) {
    final createdBy = data['created_by'];
    if (createdBy is! List) {
      return null;
    }

    final names = createdBy
        .whereType<Map>()
        .map((entry) => (entry['name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isEmpty) {
      return null;
    }
    return names.join(', ');
  }

  String? _formatDate(dynamic rawDate) {
    if (rawDate == null) return null;
    final dateStr = rawDate.toString().trim();
    if (dateStr.isEmpty) return null;
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    } catch (_) {
      return dateStr;
    }
  }

  Future<MediaDetailsInfo?> getMediaDetails(
    String mediaId,
    String mediaType,
  ) async {
    if (!_hasToken || mediaId.trim().isEmpty) return null;
    final type = mediaType == 'tv' ? 'tv' : 'movie';

    try {
      final response = await _dio.get(
        'https://api.themoviedb.org/3/$type/$mediaId',
        queryParameters: {
          'language': _tmdbLanguage,
          'append_to_response': 'credits',
        },
        options: _tmdbOptions,
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final credits = data['credits'] is Map
            ? Map<String, dynamic>.from(data['credits'] as Map)
            : null;

        final genres = (data['genres'] as List?)
            ?.map((e) => e is Map ? (e['name'] ?? '').toString() : '')
            .where((name) => name.isNotEmpty)
            .toList() ?? const <String>[];

        final productionCompanies = (data['production_companies'] as List?)
            ?.map((e) => e is Map ? (e['name'] ?? '').toString() : '')
            .where((name) => name.isNotEmpty)
            .toList() ?? const <String>[];

        List<MediaItem> relatedItems = [];
        bool isCollection = false;

        if (type == 'movie') {
          final belongsToCollection = data['belongs_to_collection'];
          if (belongsToCollection is Map) {
            final collectionId = belongsToCollection['id'];
            if (collectionId != null) {
              try {
                final collResponse = await _dio.get(
                  'https://api.themoviedb.org/3/collection/$collectionId',
                  queryParameters: {'language': _tmdbLanguage},
                  options: _tmdbOptions,
                );
                if (collResponse.statusCode == 200 && collResponse.data is Map) {
                  final collData = collResponse.data;
                  final parts = collData['parts'];
                  if (parts is List) {
                    relatedItems = parts
                        .whereType<Map>()
                        .map((json) => MediaItem.fromTmdbJson({...json, 'media_type': 'movie'}))
                        .where((item) => item.id != mediaId)
                        .toList();
                    isCollection = true;
                  }
                }
              } catch (e) {
                developer.log('Collection fetch failed: $e', name: 'SearchRepository');
              }
            }
          }

          if (relatedItems.isEmpty) {
            try {
              final recResponse = await _dio.get(
                'https://api.themoviedb.org/3/movie/$mediaId/recommendations',
                queryParameters: {'language': _tmdbLanguage, 'page': 1},
                options: _tmdbOptions,
              );
              if (recResponse.statusCode == 200 && recResponse.data is Map) {
                final results = recResponse.data['results'];
                if (results is List) {
                  relatedItems = results
                      .whereType<Map>()
                      .map((json) => MediaItem.fromTmdbJson({...json, 'media_type': 'movie'}))
                      .toList();
                }
              }
            } catch (e) {
              developer.log('Recommendations fetch failed: $e', name: 'SearchRepository');
            }
          }
        } else {
          try {
            final recResponse = await _dio.get(
              'https://api.themoviedb.org/3/tv/$mediaId/recommendations',
              queryParameters: {'language': _tmdbLanguage, 'page': 1},
              options: _tmdbOptions,
            );
            if (recResponse.statusCode == 200 && recResponse.data is Map) {
              final results = recResponse.data['results'];
              if (results is List) {
                relatedItems = results
                    .whereType<Map>()
                    .map((json) => MediaItem.fromTmdbJson({...json, 'media_type': 'tv'}))
                    .toList();
              }
            }
          } catch (e) {
            developer.log('TV Recommendations fetch failed: $e', name: 'SearchRepository');
          }
        }

        return MediaDetailsInfo(
          mediaType: type,
          runtimeMinutes: _extractRuntimeMinutes(data, type),
          castNames: _extractCastNames(credits),
          directorName: _extractCrewName(credits, job: 'Director'),
          creatorName: type == 'tv'
              ? _extractCreatorName(data) ??
                    _extractCrewName(credits, job: 'Director')
              : null,
          description: (data['overview'] ?? '').toString().trim().isEmpty
              ? null
              : (data['overview'] ?? '').toString().trim(),
          rating: data['vote_average'] is num
              ? (data['vote_average'] as num).toDouble()
              : null,
          releaseDate: _formatDate(data['release_date'] ?? data['first_air_date']),
          genres: genres,
          productionCompanies: productionCompanies,
          relatedItems: relatedItems,
          isCollection: isCollection,
        );
      }
    } catch (e) {
      developer.log('Media details fetch failed: $e', name: 'SearchRepository');
    }

    return null;
  }

  Future<List<MediaItem>> _getPersonCredits(dynamic personId, String personName) async {
    if (!_hasToken) return [];
    try {
      final response = await _dio.get(
        'https://api.themoviedb.org/3/person/$personId/combined_credits',
        queryParameters: {'language': _tmdbLanguage},
        options: _tmdbOptions,
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final cast = data['cast'] as List? ?? [];
        final crew = data['crew'] as List? ?? [];

        final List<MediaItem> items = [];

        for (final json in cast) {
          if (json is Map) {
            final map = Map<String, dynamic>.from(json);
            final mediaType = map['media_type'];
            if (mediaType == 'movie' || mediaType == 'tv') {
              items.add(MediaItem.fromTmdbJson({...map, 'media_type': mediaType}));
            }
          }
        }

        for (final json in crew) {
          if (json is Map) {
            final map = Map<String, dynamic>.from(json);
            final job = map['job'] as String? ?? '';
            final isDirectorOrWriter = job.toLowerCase() == 'director' || 
                                       job.toLowerCase() == 'writer' || 
                                       job.toLowerCase() == 'producer';
            if (isDirectorOrWriter) {
              final mediaType = map['media_type'];
              if (mediaType == 'movie' || mediaType == 'tv') {
                items.add(MediaItem.fromTmdbJson({...map, 'media_type': mediaType}));
              }
            }
          }
        }

        items.sort((a, b) {
          final aRating = a.rating ?? 0.0;
          final bRating = b.rating ?? 0.0;
          return bRating.compareTo(aRating);
        });

        return items.take(25).toList();
      }
    } catch (e) {
      developer.log('Error fetching person credits: $e', name: 'SearchRepository');
    }
    return [];
  }

  StudioConfig? _findStudioConfig(String query) {
    final q = query.trim().toLowerCase();
    for (final studio in studios) {
      if (q == studio.key.toLowerCase() ||
          q == studio.name.toLowerCase() ||
          studio.name.toLowerCase().contains(q) ||
          q.contains(studio.key.toLowerCase())) {
        return studio;
      }
    }
    return null;
  }

  Future<List<MediaItem>> getMediaByStudio(StudioConfig studio) async {
    if (!_hasToken) return [];
    try {
      final List<Future<Response>> futures = [];

      // Discover movies
      if (studio.movieCompanyIds.isNotEmpty) {
        futures.add(_dio.get(
          'https://api.themoviedb.org/3/discover/movie',
          queryParameters: {
            'language': _tmdbLanguage,
            'with_companies': studio.movieCompanyIds.join('|'),
            'sort_by': 'popularity.desc',
            'page': 1,
          },
          options: _tmdbOptions,
        ));
      }

      // Discover series
      if (studio.tvNetworkIds.isNotEmpty || (studio.tvCompanyIds != null && studio.tvCompanyIds!.isNotEmpty)) {
        final queryParams = <String, dynamic>{
          'language': _tmdbLanguage,
          'sort_by': 'popularity.desc',
          'page': 1,
        };
        if (studio.tvNetworkIds.isNotEmpty) {
          queryParams['with_networks'] = studio.tvNetworkIds.join('|');
        } else if (studio.tvCompanyIds != null && studio.tvCompanyIds!.isNotEmpty) {
          queryParams['with_companies'] = studio.tvCompanyIds!.join('|');
        }

        futures.add(_dio.get(
          'https://api.themoviedb.org/3/discover/tv',
          queryParameters: queryParams,
          options: _tmdbOptions,
        ));
      }

      final responses = await Future.wait(futures);
      final List<MediaItem> results = [];

      for (final response in responses) {
        if (response.statusCode == 200 && response.data is Map) {
          final data = response.data;
          final isMovieQuery = response.requestOptions.path.contains('/movie');
          final mediaType = isMovieQuery ? 'movie' : 'tv';

          if (data['results'] is List) {
            for (final json in data['results']) {
              if (json is Map) {
                results.add(MediaItem.fromTmdbJson({
                  ...Map<String, dynamic>.from(json),
                  'media_type': mediaType,
                }));
              }
            }
          }
        }
      }

      results.sort((a, b) {
        final aRating = a.rating ?? 0.0;
        final bRating = b.rating ?? 0.0;
        return bRating.compareTo(aRating);
      });

      return results;
    } catch (e) {
      developer.log('Error fetching media by studio: $e', name: 'SearchRepository');
    }
    return [];
  }

  Future<List<MediaItem>> search(String query) async {
    if (!_hasToken) return [];
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    final matchedStudio = _findStudioConfig(trimmedQuery);
    List<MediaItem> studioResults = [];
    if (matchedStudio != null) {
      studioResults = await getMediaByStudio(matchedStudio);
    }

    try {
      final response = await _dio.get(
        'https://api.themoviedb.org/3/search/multi',
        queryParameters: {'query': trimmedQuery, 'language': _tmdbLanguage, 'page': 1},
        options: _tmdbOptions,
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        if (data['results'] != null) {
          final List<dynamic> rawItems = data['results'];
          final List<MediaItem> results = [];
          final List<Map<String, dynamic>> people = [];

          // Add studio results first
          results.addAll(studioResults);

          for (final json in rawItems) {
            if (json is Map) {
              final map = Map<String, dynamic>.from(json);
              final mediaType = map['media_type'];
              if (mediaType == 'movie' || mediaType == 'tv') {
                results.add(MediaItem.fromTmdbJson(map));
              } else if (mediaType == 'person') {
                people.add(map);
              }
            }
          }

          final Map<String, String> itemToPersonMap = {};

          if (people.isNotEmpty) {
            final topPeople = people.take(2).toList();
            final List<Future<List<MediaItem>>> creditFutures = [];

            for (final person in topPeople) {
              final personId = person['id'];
              final personName = person['name'] ?? '';
              creditFutures.add(_getPersonCredits(personId, personName));
            }

            final creditsLists = await Future.wait(creditFutures);
            for (var i = 0; i < topPeople.length; i++) {
              final personName = topPeople[i]['name'] ?? '';
              final credits = creditsLists[i];
              for (final item in credits) {
                final key = '${item.type}:${item.id}';
                itemToPersonMap[key] = personName;
                results.add(item);
              }
            }
          }

          final seen = <String>{};
          final deduped = <MediaItem>[];
          for (final item in results) {
            if (item.id.isEmpty) continue;
            final key = '${item.type}:${item.id}';
            if (seen.add(key)) {
              deduped.add(item);
            }
          }

          return _fuzzySortResults(trimmedQuery, deduped, itemToPersonMap);
        }
      }
    } catch (e) {
      developer.log('Error searching TMDB: $e', name: 'SearchRepository');
    }
    return [];
  }

  List<MediaItem> _fuzzySortResults(
    String query,
    List<MediaItem> items,
    Map<String, String> itemToPersonMap,
  ) {
    if (query.isEmpty) return items;

    final scoredItems = <MapEntry<MediaItem, double>>[];

    for (final item in items) {
      final key = '${item.type}:${item.id}';
      final matchedPerson = itemToPersonMap[key];

      final titleScore = _calculateFuzzyScore(query, item.title);
      
      var descScore = 0.0;
      if (item.description != null && item.description!.isNotEmpty) {
        descScore = _calculateFuzzyScore(query, item.description!) * 0.4;
      }

      var personScore = 0.0;
      if (matchedPerson != null && matchedPerson.isNotEmpty) {
        personScore = _calculateFuzzyScore(query, matchedPerson) * 0.95;
      }

      final finalScore = [titleScore, descScore, personScore].reduce((a, b) => a > b ? a : b);

      scoredItems.add(MapEntry(item, finalScore));
    }

    scoredItems.sort((a, b) => b.value.compareTo(a.value));
    return scoredItems.map((entry) => entry.key).toList();
  }

  double _calculateFuzzyScore(String query, String target) {
    final q = query.trim().toLowerCase();
    final t = target.trim().toLowerCase();
    if (q == t) return 1.0;

    if (t.contains(q)) {
      return 0.8 + (q.length / t.length) * 0.2;
    }

    final words = t.split(RegExp(r'\s+'));
    for (final word in words) {
      if (word.startsWith(q)) {
        return 0.75 + (q.length / word.length) * 0.15;
      }
    }

    return _jaroWinkler(q, t);
  }

  double _jaroWinkler(String s1, String s2) {
    if (s1 == s2) return 1.0;

    final len1 = s1.length;
    final len2 = s2.length;
    if (len1 == 0 || len2 == 0) return 0.0;

    final matchDistance = (len1 > len2 ? len1 : len2) ~/ 2 - 1;
    final matchDistanceVal = matchDistance < 0 ? 0 : matchDistance;

    final s1Matches = List<bool>.filled(len1, false);
    final s2Matches = List<bool>.filled(len2, false);

    var matches = 0;
    var transpositions = 0;

    for (var i = 0; i < len1; i++) {
      final start = (i - matchDistanceVal).clamp(0, len1);
      final end = (i + matchDistanceVal + 1).clamp(0, len2);
      for (var j = start; j < end; j++) {
        if (s2Matches[j]) continue;
        if (s1[i] != s2[j]) continue;
        s1Matches[i] = true;
        s2Matches[j] = true;
        matches++;
        break;
      }
    }

    if (matches == 0) return 0.0;

    var k = 0;
    for (var i = 0; i < len1; i++) {
      if (!s1Matches[i]) continue;
      while (!s2Matches[k]) {
        k++;
      }
      if (s1[i] != s2[k]) transpositions++;
      k++;
    }

    final m = matches.toDouble();
    final jaro = (m / len1 + m / len2 + (m - transpositions / 2.0) / m) / 3.0;

    var prefix = 0;
    final maxPrefix = len1 < len2 ? (len1 < 4 ? len1 : 4) : (len2 < 4 ? len2 : 4);
    for (var i = 0; i < maxPrefix; i++) {
      if (s1[i] == s2[i]) {
        prefix++;
      } else {
        break;
      }
    }

    return jaro + prefix * 0.1 * (1.0 - jaro);
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

  Future<LatestEpisodeInfo?> getLatestEpisodeInfo(String seriesId) async {
    if (!_hasToken || seriesId.trim().isEmpty) return null;
    try {
      final response = await _dio.get(
        'https://api.themoviedb.org/3/tv/$seriesId',
        queryParameters: {'language': _tmdbLanguage},
        options: _tmdbOptions,
      );
      if (response.statusCode == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final rawEpisode = data['last_episode_to_air'];
        if (rawEpisode is Map) {
          final episode = LatestEpisodeInfo.fromTmdbJson(
            Map<String, dynamic>.from(rawEpisode),
          );
          if (episode.seasonNumber > 0 && episode.episodeNumber > 0) {
            return episode;
          }
        }
      }
    } catch (e) {
      developer.log(
        'Latest episode fetch failed: $e',
        name: 'SearchRepository',
      );
    }
    return null;
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

      final movies =
          (responses[0].data['results'] as List<dynamic>? ?? const [])
              .map(
                (json) =>
                    MediaItem.fromTmdbJson({...json, 'media_type': 'movie'}),
              )
              .toList();
      final series =
          (responses[1].data['results'] as List<dynamic>? ?? const [])
              .map(
                (json) => MediaItem.fromTmdbJson({...json, 'media_type': 'tv'}),
              )
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
              (json) => MediaItem.fromTmdbJson({...json, 'media_type': type}),
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
