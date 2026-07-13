import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../search/domain/entities/media_item.dart';
import '../../../search/presentation/providers/search_provider.dart';
import '../../../search/data/repositories/search_repository.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../library/presentation/providers/watched_provider.dart';

final trendingMoviesProvider = FutureProvider<List<MediaItem>>((ref) async {
  final repo = ref.watch(searchRepositoryProvider);
  return repo.getTrendingMovies();
});

final trendingSeriesProvider = FutureProvider<List<MediaItem>>((ref) async {
  final repo = ref.watch(searchRepositoryProvider);
  return repo.getTrendingSeries();
});

final animationMoviesProvider = FutureProvider<List<MediaItem>>((ref) async {
  return ref.watch(searchRepositoryProvider).getMoviesByGenre(16);
});

final horrorMoviesProvider = FutureProvider<List<MediaItem>>((ref) async {
  return ref.watch(searchRepositoryProvider).getMoviesByGenre(27);
});

final dramaMoviesProvider = FutureProvider<List<MediaItem>>((ref) async {
  return ref.watch(searchRepositoryProvider).getMoviesByGenre(18);
});

final thrillerMoviesProvider = FutureProvider<List<MediaItem>>((ref) async {
  return ref.watch(searchRepositoryProvider).getMoviesByGenre(53);
});

final animeSeriesProvider = FutureProvider<List<MediaItem>>((ref) async {
  return ref.watch(searchRepositoryProvider).getSeriesByGenre(16);
});

final featuredWeeklyProvider = FutureProvider<List<MediaItem>>((ref) async {
  final repo = ref.watch(searchRepositoryProvider);
  return repo.getFeaturedWeeklyHighRated();
});

final classicsProvider = FutureProvider<List<MediaItem>>((ref) async {
  return ref.watch(searchRepositoryProvider).getClassicMovies();
});

final westernProvider = FutureProvider<List<MediaItem>>((ref) async {
  return ref.watch(searchRepositoryProvider).getWesternMovies();
});

final movies1950sProvider = FutureProvider<List<MediaItem>>((ref) async {
  return ref.watch(
    searchRepositoryProvider,
  ).getMoviesByDecade(fromYear: 1950, toYear: 1959, minVote: 6.8);
});

final movies1960sProvider = FutureProvider<List<MediaItem>>((ref) async {
  return ref.watch(
    searchRepositoryProvider,
  ).getMoviesByDecade(fromYear: 1960, toYear: 1969, minVote: 6.8);
});

final movies1970sProvider = FutureProvider<List<MediaItem>>((ref) async {
  return ref.watch(
    searchRepositoryProvider,
  ).getMoviesByDecade(fromYear: 1970, toYear: 1979, minVote: 6.8);
});

final movies1980sProvider = FutureProvider<List<MediaItem>>((ref) async {
  return ref.watch(
    searchRepositoryProvider,
  ).getMoviesByDecade(fromYear: 1980, toYear: 1989, minVote: 6.8);
});

final recommendedForYouProvider = FutureProvider<List<MediaItem>>((ref) async {
  ref.watch(watchHistoryChangesProvider);
  ref.watch(watchedChangesProvider);

  final repo = ref.watch(searchRepositoryProvider);
  final history = ref.read(watchHistoryRepositoryProvider).getAllHistory();
  final manuallyWatched = ref.watch(watchedProvider);

  if (history.isEmpty && manuallyWatched.isEmpty) {
    return [];
  }

  final seed = <String>{};
  final watchedIds = <String>{};
  for (final item in history) {
    watchedIds.add(item.mediaId);
    if (seed.length < 3) {
      seed.add('${item.mediaType}:${item.mediaId}');
    }
  }

  for (final item in manuallyWatched) {
    watchedIds.add(item.id);
    if (seed.length < 3) {
      seed.add('${item.type}:${item.id}');
    }
  }

  final merged = <MediaItem>[];
  final seen = <String>{};
  for (final key in seed) {
    final parts = key.split(':');
    if (parts.length != 2) {
      continue;
    }
    final type = parts[0];
    final id = parts[1];
    final recs = await repo.getRecommendedForMedia(
      id,
      mediaType: type == 'tv' ? 'tv' : 'movie',
    );

    for (final item in recs) {
      if (watchedIds.contains(item.id)) {
        continue;
      }
      final dedupeKey = '${item.type}:${item.id}';
      if (seen.contains(dedupeKey)) {
        continue;
      }
      seen.add(dedupeKey);
      merged.add(item);
      if (merged.length >= 30) {
        return merged;
      }
    }
  }

  return merged;
});

final studioMediaProvider = FutureProvider.family<List<MediaItem>, String>((ref, studioKey) async {
  final repo = ref.watch(searchRepositoryProvider);
  final studio = studios.firstWhere(
    (s) => s.key == studioKey,
    orElse: () => studios.first,
  );
  return repo.getMediaByStudio(studio);
});

final categoryMediaProvider = FutureProvider.family<List<MediaItem>, String>((ref, key) async {
  if (key.startsWith('studio_')) {
    final studioKey = key.replaceFirst('studio_', '');
    return ref.watch(studioMediaProvider(studioKey).future);
  }
  if (key.startsWith('actor_')) {
    final actorName = key.replaceFirst('actor_', '');
    return ref.watch(searchRepositoryProvider).getMediaByActor(actorName);
  }
  if (key.startsWith('company_')) {
    final companyName = key.replaceFirst('company_', '');
    return ref.watch(searchRepositoryProvider).getMediaByProductionCompany(companyName);
  }
  if (key.startsWith('genre_')) {
    final genreName = key.replaceFirst('genre_', '');
    return ref.watch(searchRepositoryProvider).getMediaByGenreName(genreName);
  }
  switch (key) {
    case 'recommended_for_you':
      return ref.watch(recommendedForYouProvider.future);
    case 'trending_movies':
      return ref.watch(trendingMoviesProvider.future);
    case 'trending_series':
      return ref.watch(trendingSeriesProvider.future);
    case 'animation_movies':
      return ref.watch(animationMoviesProvider.future);
    case 'anime_series':
      return ref.watch(animeSeriesProvider.future);
    case 'horror_movies':
      return ref.watch(horrorMoviesProvider.future);
    case 'drama_movies':
      return ref.watch(dramaMoviesProvider.future);
    case 'thriller_movies':
      return ref.watch(thrillerMoviesProvider.future);
    case 'classic_movies':
      return ref.watch(classicsProvider.future);
    case 'western_movies':
      return ref.watch(westernProvider.future);
    case 'movies_1950s':
      return ref.watch(movies1950sProvider.future);
    case 'movies_1960s':
      return ref.watch(movies1960sProvider.future);
    case 'movies_1970s':
      return ref.watch(movies1970sProvider.future);
    case 'movies_1980s':
      return ref.watch(movies1980sProvider.future);
    default:
      return [];
  }
});
