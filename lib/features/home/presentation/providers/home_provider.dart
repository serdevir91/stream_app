import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../search/domain/entities/media_item.dart';
import '../../../search/presentation/providers/search_provider.dart';

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
