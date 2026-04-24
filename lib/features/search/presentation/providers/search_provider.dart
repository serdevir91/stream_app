import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/media_item.dart';
import '../../data/repositories/search_repository.dart';
import '../../../sources/presentation/providers/sources_provider.dart';

final dioProvider = Provider<Dio>((ref) {
  return Dio();
});

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return SearchRepository(dio);
});

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

final searchResultsProvider = FutureProvider<List<MediaItem>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  final sources = ref.watch(sourcesProvider);
  
  if (query.isEmpty) return [];

  final repository = ref.watch(searchRepositoryProvider);
  return repository.search(query, sources);
});
