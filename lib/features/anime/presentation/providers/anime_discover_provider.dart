import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/presentation/providers/library_provider.dart';
import '../../../library/presentation/providers/watched_provider.dart';
import '../../domain/models/anime_item.dart';
import '../../data/services/jikan_anime_api_service.dart';
import 'anime_providers.dart';

class AnimeDiscoverFilter {
  final String? genre;
  final String format; // 'all', 'tv', 'movie', 'ova'
  final String status; // 'all', 'airing', 'complete', 'upcoming'
  final double minScore; // 0.0, 7.0, 7.5, 8.0, 8.5
  final String sortBy; // 'popularity', 'score', 'airing'

  const AnimeDiscoverFilter({
    this.genre,
    this.format = 'all',
    this.status = 'all',
    this.minScore = 0.0,
    this.sortBy = 'popularity',
  });

  AnimeDiscoverFilter copyWith({
    String? Function()? genre,
    String? format,
    String? status,
    double? minScore,
    String? sortBy,
  }) {
    return AnimeDiscoverFilter(
      genre: genre != null ? genre() : this.genre,
      format: format ?? this.format,
      status: status ?? this.status,
      minScore: minScore ?? this.minScore,
      sortBy: sortBy ?? this.sortBy,
    );
  }
}

class AnimeDiscoverState {
  final List<AnimeItem> cards;
  final List<AnimeItem> undoStack;
  final AnimeDiscoverFilter filter;
  final bool isLoading;
  final bool isInitialLoading;
  final int page;
  final String? errorMessage;

  const AnimeDiscoverState({
    required this.cards,
    required this.undoStack,
    required this.filter,
    this.isLoading = false,
    this.isInitialLoading = false,
    this.page = 1,
    this.errorMessage,
  });

  AnimeDiscoverState copyWith({
    List<AnimeItem>? cards,
    List<AnimeItem>? undoStack,
    AnimeDiscoverFilter? filter,
    bool? isLoading,
    bool? isInitialLoading,
    int? page,
    String? errorMessage,
  }) {
    return AnimeDiscoverState(
      cards: cards ?? this.cards,
      undoStack: undoStack ?? this.undoStack,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      page: page ?? this.page,
      errorMessage: errorMessage,
    );
  }
}

class AnimeDiscoverNotifier extends Notifier<AnimeDiscoverState> {
  late JikanAnimeApiService _api;

  @override
  AnimeDiscoverState build() {
    _api = ref.watch(jikanApiServiceProvider);
    state = const AnimeDiscoverState(
      cards: [],
      undoStack: [],
      filter: AnimeDiscoverFilter(),
      isInitialLoading: true,
    );
    Future.microtask(() => _loadInitial());
    return state;
  }

  Future<void> _loadInitial() async {
    state = state.copyWith(isInitialLoading: true, errorMessage: null);
    try {
      final items = await _fetchCards(page: 1);
      state = state.copyWith(
        cards: items,
        page: 2,
        isInitialLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isInitialLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<List<AnimeItem>> _fetchCards({required int page}) async {
    final filter = state.filter;

    // Build params guarded against obscure/unknown anime with only 1-5 votes
    final typeParam = filter.format == 'all' ? null : filter.format;
    final statusParam = filter.status == 'all' ? null : filter.status;
    final genresParam = filter.genre;

    if (filter.format == 'movie' && filter.genre == null) {
      return _api.getTopMovies(page: page, limit: 25);
    }

    if (filter.sortBy == 'airing') {
      return _api.getTopAnime(
        filter: 'airing',
        page: page,
        limit: 25,
      );
    }

    if (filter.sortBy == 'score') {
      // Guarded top rated: query with minScore to avoid 10-vote obscure entries
      return _api.searchAnime(
        query: '',
        type: typeParam,
        status: statusParam,
        genres: genresParam,
        orderBy: 'score',
        sort: 'desc',
        page: page,
        limit: 25,
      );
    }

    // Default: Popularity (ensures widely known & reviewed anime)
    return _api.searchAnime(
      query: '',
      type: typeParam,
      status: statusParam,
      genres: genresParam,
      orderBy: 'members',
      sort: 'desc',
      page: page,
      limit: 25,
    );
  }

  Future<void> loadMore() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);
    try {
      final newItems = await _fetchCards(page: state.page);
      final currentIds = state.cards.map((e) => e.malId).toSet();
      final deduped = newItems.where((e) => !currentIds.contains(e.malId)).toList();

      state = state.copyWith(
        cards: [...state.cards, ...deduped],
        page: state.page + 1,
        isLoading: false,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> swipeWatched(AnimeItem item) async {
    await ref.read(watchedProvider.notifier).toggle(item.toMediaItem());
    final updatedCards = List<AnimeItem>.from(state.cards)..remove(item);
    final updatedUndo = List<AnimeItem>.from(state.undoStack)..add(item);
    state = state.copyWith(cards: updatedCards, undoStack: updatedUndo);
    if (state.cards.length <= 4) {
      loadMore();
    }
  }

  Future<void> swipeMyList(AnimeItem item) async {
    await ref.read(libraryProvider.notifier).toggle(item.toMediaItem());
    final updatedCards = List<AnimeItem>.from(state.cards)..remove(item);
    final updatedUndo = List<AnimeItem>.from(state.undoStack)..add(item);
    state = state.copyWith(cards: updatedCards, undoStack: updatedUndo);
    if (state.cards.length <= 4) {
      loadMore();
    }
  }

  void skip(AnimeItem item) {
    final updatedCards = List<AnimeItem>.from(state.cards)..remove(item);
    final updatedUndo = List<AnimeItem>.from(state.undoStack)..add(item);
    state = state.copyWith(cards: updatedCards, undoStack: updatedUndo);
    if (state.cards.length <= 4) {
      loadMore();
    }
  }

  void undo() {
    if (state.undoStack.isEmpty) return;
    final updatedUndo = List<AnimeItem>.from(state.undoStack);
    final restoredItem = updatedUndo.removeLast();
    final updatedCards = [restoredItem, ...state.cards];
    state = state.copyWith(cards: updatedCards, undoStack: updatedUndo);
  }

  void setGenre(String? genre) {
    if (state.filter.genre == genre) return;
    state = state.copyWith(
      filter: state.filter.copyWith(genre: () => genre),
      cards: [],
      undoStack: [],
      page: 1,
    );
    _loadInitial();
  }

  void setFormat(String format) {
    if (state.filter.format == format) return;
    state = state.copyWith(
      filter: state.filter.copyWith(format: format),
      cards: [],
      undoStack: [],
      page: 1,
    );
    _loadInitial();
  }

  void setStatus(String status) {
    if (state.filter.status == status) return;
    state = state.copyWith(
      filter: state.filter.copyWith(status: status),
      cards: [],
      undoStack: [],
      page: 1,
    );
    _loadInitial();
  }

  void setMinScore(double minScore) {
    if (state.filter.minScore == minScore) return;
    state = state.copyWith(
      filter: state.filter.copyWith(minScore: minScore),
      cards: [],
      undoStack: [],
      page: 1,
    );
    _loadInitial();
  }

  void setSortBy(String sortBy) {
    if (state.filter.sortBy == sortBy) return;
    state = state.copyWith(
      filter: state.filter.copyWith(sortBy: sortBy),
      cards: [],
      undoStack: [],
      page: 1,
    );
    _loadInitial();
  }
}

final animeDiscoverProvider =
    NotifierProvider<AnimeDiscoverNotifier, AnimeDiscoverState>(
  AnimeDiscoverNotifier.new,
);
