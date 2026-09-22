import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../library/presentation/providers/library_provider.dart';
import '../../../library/presentation/providers/watched_provider.dart';
import '../../../search/data/repositories/search_repository.dart';
import '../../../search/domain/entities/media_item.dart';
import '../../../search/presentation/providers/search_provider.dart';

class DiscoverGenre {
  final int? id;
  final String key;
  final String labelTr;
  final String labelEn;

  const DiscoverGenre({
    required this.id,
    required this.key,
    required this.labelTr,
    required this.labelEn,
  });
}

const List<DiscoverGenre> discoverGenres = [
  DiscoverGenre(id: null, key: 'all', labelTr: 'Hepsi', labelEn: 'All'),
  DiscoverGenre(id: 27, key: 'horror', labelTr: 'Korku', labelEn: 'Horror'),
  DiscoverGenre(id: 28, key: 'action', labelTr: 'Aksiyon', labelEn: 'Action'),
  DiscoverGenre(id: 878, key: 'scifi', labelTr: 'Bilim Kurgu', labelEn: 'Sci-Fi'),
  DiscoverGenre(id: 53, key: 'thriller', labelTr: 'Gerilim', labelEn: 'Thriller'),
  DiscoverGenre(id: 35, key: 'comedy', labelTr: 'Komedi', labelEn: 'Comedy'),
  DiscoverGenre(id: 18, key: 'drama', labelTr: 'Dram', labelEn: 'Drama'),
  DiscoverGenre(id: 16, key: 'animation', labelTr: 'Animasyon', labelEn: 'Animation'),
  DiscoverGenre(id: 10749, key: 'romance', labelTr: 'Romantik', labelEn: 'Romance'),
  DiscoverGenre(id: 12, key: 'adventure', labelTr: 'Macera', labelEn: 'Adventure'),
  DiscoverGenre(id: 80, key: 'crime', labelTr: 'Suç', labelEn: 'Crime'),
  DiscoverGenre(id: 9648, key: 'mystery', labelTr: 'Gizem', labelEn: 'Mystery'),
  DiscoverGenre(id: 99, key: 'documentary', labelTr: 'Belgesel', labelEn: 'Documentary'),
];

class DiscoverFilter {
  final int? genreId;
  final String genreKey;
  final String mediaType; // 'all', 'movie', 'tv'
  final double minRating; // 0.0, 7.0, 7.5, 8.0
  final String sortBy; // 'rating', 'popularity'

  const DiscoverFilter({
    this.genreId,
    this.genreKey = 'all',
    this.mediaType = 'all',
    this.minRating = 0.0,
    this.sortBy = 'rating',
  });

  DiscoverFilter copyWith({
    int? Function()? genreId,
    String? genreKey,
    String? mediaType,
    double? minRating,
    String? sortBy,
  }) {
    return DiscoverFilter(
      genreId: genreId != null ? genreId() : this.genreId,
      genreKey: genreKey ?? this.genreKey,
      mediaType: mediaType ?? this.mediaType,
      minRating: minRating ?? this.minRating,
      sortBy: sortBy ?? this.sortBy,
    );
  }
}

class DiscoverState {
  final List<MediaItem> cards;
  final List<MediaItem> undoStack;
  final DiscoverFilter filter;
  final bool isLoading;
  final bool isInitialLoading;
  final int page;
  final String? errorMessage;

  const DiscoverState({
    required this.cards,
    required this.undoStack,
    required this.filter,
    this.isLoading = false,
    this.isInitialLoading = false,
    this.page = 1,
    this.errorMessage,
  });

  DiscoverState copyWith({
    List<MediaItem>? cards,
    List<MediaItem>? undoStack,
    DiscoverFilter? filter,
    bool? isLoading,
    bool? isInitialLoading,
    int? page,
    String? errorMessage,
  }) {
    return DiscoverState(
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

class DiscoverNotifier extends Notifier<DiscoverState> {
  late SearchRepository _searchRepo;

  @override
  DiscoverState build() {
    _searchRepo = ref.watch(searchRepositoryProvider);
    state = const DiscoverState(
      cards: [],
      undoStack: [],
      filter: DiscoverFilter(),
      isInitialLoading: true,
    );
    Future.microtask(() => _loadInitial());
    return state;
  }

  Future<void> _loadInitial() async {
    state = state.copyWith(isInitialLoading: true, errorMessage: null);
    try {
      final items = await _searchRepo.discoverCards(
        genreId: state.filter.genreId,
        mediaType: state.filter.mediaType,
        minRating: state.filter.minRating > 0 ? state.filter.minRating : null,
        sortBy: state.filter.sortBy,
        page: 1,
      );
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

  Future<void> loadMore() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);
    try {
      final newItems = await _searchRepo.discoverCards(
        genreId: state.filter.genreId,
        mediaType: state.filter.mediaType,
        minRating: state.filter.minRating > 0 ? state.filter.minRating : null,
        sortBy: state.filter.sortBy,
        page: state.page,
      );

      final currentIds = state.cards.map((e) => '${e.type}:${e.id}').toSet();
      final deduped = newItems.where((e) => !currentIds.contains('${e.type}:${e.id}')).toList();

      state = state.copyWith(
        cards: [...state.cards, ...deduped],
        page: state.page + 1,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> swipeWatched(MediaItem item) async {
    await ref.read(watchedProvider.notifier).toggle(item);
    final updatedCards = List<MediaItem>.from(state.cards)..remove(item);
    final updatedUndo = List<MediaItem>.from(state.undoStack)..add(item);
    state = state.copyWith(cards: updatedCards, undoStack: updatedUndo);
    if (state.cards.length <= 4) {
      loadMore();
    }
  }

  Future<void> swipeMyList(MediaItem item) async {
    await ref.read(libraryProvider.notifier).toggle(item);
    final updatedCards = List<MediaItem>.from(state.cards)..remove(item);
    final updatedUndo = List<MediaItem>.from(state.undoStack)..add(item);
    state = state.copyWith(cards: updatedCards, undoStack: updatedUndo);
    if (state.cards.length <= 4) {
      loadMore();
    }
  }

  void skip(MediaItem item) {
    final updatedCards = List<MediaItem>.from(state.cards)..remove(item);
    final updatedUndo = List<MediaItem>.from(state.undoStack)..add(item);
    state = state.copyWith(cards: updatedCards, undoStack: updatedUndo);
    if (state.cards.length <= 4) {
      loadMore();
    }
  }

  void undo() {
    if (state.undoStack.isEmpty) return;
    final updatedUndo = List<MediaItem>.from(state.undoStack);
    final restoredItem = updatedUndo.removeLast();
    final updatedCards = [restoredItem, ...state.cards];
    state = state.copyWith(cards: updatedCards, undoStack: updatedUndo);
  }

  void setGenre(DiscoverGenre genre) {
    if (state.filter.genreId == genre.id && state.filter.genreKey == genre.key) return;
    state = state.copyWith(
      filter: state.filter.copyWith(
        genreId: () => genre.id,
        genreKey: genre.key,
      ),
      cards: [],
      undoStack: [],
      page: 1,
    );
    _loadInitial();
  }

  void setMediaType(String mediaType) {
    if (state.filter.mediaType == mediaType) return;
    state = state.copyWith(
      filter: state.filter.copyWith(mediaType: mediaType),
      cards: [],
      undoStack: [],
      page: 1,
    );
    _loadInitial();
  }

  void setMinRating(double rating) {
    if (state.filter.minRating == rating) return;
    state = state.copyWith(
      filter: state.filter.copyWith(minRating: rating),
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

final discoverProvider = NotifierProvider<DiscoverNotifier, DiscoverState>(
  DiscoverNotifier.new,
);
