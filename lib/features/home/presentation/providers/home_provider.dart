import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../search/domain/entities/media_item.dart';
import '../../../search/presentation/providers/search_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';

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

  final repo = ref.watch(searchRepositoryProvider);
  final history = ref.read(watchHistoryRepositoryProvider).getAllHistory();
  if (history.isEmpty) {
    return [];
  }

  final seed = <String>{};
  final watchedIds = <String>{};
  for (final item in history) {
    watchedIds.add(item.mediaId);
    if (seed.length >= 3) {
      continue;
    }
    seed.add('${item.mediaType}:${item.mediaId}');
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
