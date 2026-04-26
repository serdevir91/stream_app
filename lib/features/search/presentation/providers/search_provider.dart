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
    state = query;
  }
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

final searchResultsProvider = FutureProvider<List<MediaItem>>((ref) async {
  final query = ref.watch(searchQueryProvider);

  if (query.isEmpty) return [];

  final repository = ref.watch(searchRepositoryProvider);
  return repository.search(query);
});

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
