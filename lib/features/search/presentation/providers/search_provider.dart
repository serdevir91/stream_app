import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../domain/entities/media_item.dart';
import '../../data/repositories/search_repository.dart';

final dioProvider = Provider<Dio>((ref) {
  return Dio();
});

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  final dio = ref.watch(dioProvider);
  final settings = ref.watch(appSettingsProvider);
  final tmdbLanguage = settings.appLanguage == 'en' ? 'en-US' : 'tr-TR';
  return SearchRepository(
    dio,
    tmdbAccessToken: settings.tmdbAccessToken,
    tmdbLanguage: tmdbLanguage,
  );
});

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query.trim();
  }
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

class RecentSearchesNotifier extends Notifier<List<String>> {
  static const int _maxItems = 8;

  @override
  List<String> build() => const [];

  void addQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final next = <String>[trimmed];
    for (final item in state) {
      if (item.toLowerCase() != trimmed.toLowerCase()) {
        next.add(item);
      }
      if (next.length >= _maxItems) {
        break;
      }
    }
    state = next;
  }

  void clear() {
    state = const [];
  }
}

final recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<String>>(
      RecentSearchesNotifier.new,
    );

final searchResultsProvider = FutureProvider<List<MediaItem>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();

  if (query.isEmpty) return [];

  final repository = ref.watch(searchRepositoryProvider);
  return repository.search(query);
});

final mixedRecommendationsProvider = FutureProvider<List<MediaItem>>((
  ref,
) async {
  final repo = ref.watch(searchRepositoryProvider);
  final token = ref.watch(appSettingsProvider).tmdbAccessToken.trim();

  final mixed = <MediaItem>[];
  if (token.isEmpty) {
    final localMovies = await repo.getLatestVidSrcMovies(page: 1);
    final localSeries = await repo.getLatestVidSrcSeries(page: 1);
    mixed.addAll(_alternateMerge(localMovies, localSeries));
    return _dedupeAndLimit(mixed, 40);
  }

  final responses = await Future.wait([
    repo.getTrendingMovies(),
    repo.getTrendingSeries(),
    repo.getLatestVidSrcMovies(page: 1),
    repo.getLatestVidSrcSeries(page: 1),
  ]);

  final trendingMovies = responses[0];
  final trendingSeries = responses[1];
  final latestMovies = responses[2];
  final latestSeries = responses[3];

  mixed.addAll(_alternateMerge(trendingMovies, trendingSeries));
  mixed.addAll(_alternateMerge(latestMovies, latestSeries));
  return _dedupeAndLimit(mixed, 40);
});

List<MediaItem> _alternateMerge(List<MediaItem> movies, List<MediaItem> series) {
  final merged = <MediaItem>[];
  final maxLen = movies.length > series.length ? movies.length : series.length;
  for (var i = 0; i < maxLen; i++) {
    if (i < movies.length) {
      merged.add(movies[i]);
    }
    if (i < series.length) {
      merged.add(series[i]);
    }
  }
  return merged;
}

List<MediaItem> _dedupeAndLimit(List<MediaItem> items, int limit) {
  final seen = <String>{};
  final result = <MediaItem>[];
  for (final item in items) {
    if (item.id.isEmpty) {
      continue;
    }
    final key = '${item.type}:${item.id}';
    if (!seen.add(key)) {
      continue;
    }
    result.add(item);
    if (result.length >= limit) {
      break;
    }
  }
  return result;
}

final seriesSeasonsProvider = FutureProvider.family<List<Season>, String>((
  ref,
  seriesId,
) async {
  final repo = ref.watch(searchRepositoryProvider);
  return repo.getSeriesSeasons(seriesId);
});

final seasonEpisodesProvider = FutureProvider.family<List<Episode>, String>((
  ref,
  args,
) async {
  final parts = args.split('_');
  final seriesId = parts[0];
  final seasonNumber = int.parse(parts[1]);
  final repo = ref.watch(searchRepositoryProvider);
  return repo.getSeasonEpisodes(seriesId, seasonNumber);
});
