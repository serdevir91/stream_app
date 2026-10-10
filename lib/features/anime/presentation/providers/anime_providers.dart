import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/addon_service_provider.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../domain/models/anime_item.dart';
import '../../domain/models/anime_episode.dart';
import '../../data/services/jikan_anime_api_service.dart';
import '../../data/providers/anime_stream_resolver.dart';

final jikanApiServiceProvider = Provider<JikanAnimeApiService>((ref) {
  return JikanAnimeApiService();
});

final animeStreamResolverProvider = Provider<AnimeStreamResolver>((ref) {
  final addonService = ref.watch(addonServiceProvider);
  final settings = ref.watch(appSettingsProvider);
  return AnimeStreamResolver(
    addonService: addonService,
    tmdbAccessToken: settings.tmdbAccessToken,
  );
});

class AnimeHomeState {
  final List<AnimeItem> spotlight;
  final List<AnimeItem> trending;
  final List<AnimeItem> popular;
  final List<AnimeItem> seasonNow;
  final List<AnimeItem> topRated;
  final List<AnimeItem> upcoming;
  final List<AnimeItem> recentlyUpdated;
  final List<String> genres;
  final String? selectedGenre;
  final List<AnimeItem> genreItems;
  final bool isLoading;
  final bool isGenreLoading;
  final String? error;

  const AnimeHomeState({
    this.spotlight = const [],
    this.trending = const [],
    this.popular = const [],
    this.seasonNow = const [],
    this.topRated = const [],
    this.upcoming = const [],
    this.recentlyUpdated = const [],
    this.genres = const [],
    this.selectedGenre,
    this.genreItems = const [],
    this.isLoading = false,
    this.isGenreLoading = false,
    this.error,
  });

  AnimeHomeState copyWith({
    List<AnimeItem>? spotlight,
    List<AnimeItem>? trending,
    List<AnimeItem>? popular,
    List<AnimeItem>? seasonNow,
    List<AnimeItem>? topRated,
    List<AnimeItem>? upcoming,
    List<AnimeItem>? recentlyUpdated,
    List<String>? genres,
    String? selectedGenre,
    List<AnimeItem>? genreItems,
    bool? isLoading,
    bool? isGenreLoading,
    String? error,
  }) {
    return AnimeHomeState(
      spotlight: spotlight ?? this.spotlight,
      trending: trending ?? this.trending,
      popular: popular ?? this.popular,
      seasonNow: seasonNow ?? this.seasonNow,
      topRated: topRated ?? this.topRated,
      upcoming: upcoming ?? this.upcoming,
      recentlyUpdated: recentlyUpdated ?? this.recentlyUpdated,
      genres: genres ?? this.genres,
      selectedGenre: selectedGenre ?? this.selectedGenre,
      genreItems: genreItems ?? this.genreItems,
      isLoading: isLoading ?? this.isLoading,
      isGenreLoading: isGenreLoading ?? this.isGenreLoading,
      error: error,
    );
  }
}

class AnimeHomeNotifier extends Notifier<AnimeHomeState> {
  @override
  AnimeHomeState build() {
    Future.microtask(() => loadHomeData());
    return const AnimeHomeState(isLoading: true);
  }

  Future<void> loadHomeData() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final api = ref.read(jikanApiServiceProvider);
      final futures = await Future.wait([
        api.getTopAnime(filter: 'airing', limit: 10), // Trending Airing
        api.getTopAnime(filter: 'bypopularity', limit: 14), // Popular
        api.getSeasonNow(limit: 14), // Current Season
        api.getTopAnime(limit: 14), // Top Rated
        api.getTopAnime(filter: 'upcoming', limit: 14), // Upcoming
        api.getRecentlyUpdated(limit: 14), // Recently Updated
        api.getGenres(), // Genres
      ]);

      final trending = futures[0] as List<AnimeItem>;
      final popular = futures[1] as List<AnimeItem>;
      final seasonNow = futures[2] as List<AnimeItem>;
      final topRated = futures[3] as List<AnimeItem>;
      final upcoming = futures[4] as List<AnimeItem>;
      final recentlyUpdated = futures[5] as List<AnimeItem>;
      final genres = futures[6] as List<String>;

      // Pick top spotlight from trending & seasonNow
      final spotlight = (seasonNow.isNotEmpty ? seasonNow.take(5).toList() : trending.take(5).toList());

      state = state.copyWith(
        spotlight: spotlight,
        trending: trending,
        popular: popular,
        seasonNow: seasonNow,
        topRated: topRated,
        upcoming: upcoming,
        recentlyUpdated: recentlyUpdated,
        genres: genres,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> selectGenre(String? genre) async {
    if (state.selectedGenre == genre) {
      state = state.copyWith(selectedGenre: null, genreItems: []);
      return;
    }

    state = state.copyWith(
      selectedGenre: genre,
      isGenreLoading: true,
      genreItems: [],
    );

    if (genre == null) {
      state = state.copyWith(isGenreLoading: false);
      return;
    }

    try {
      final api = ref.read(jikanApiServiceProvider);
      final items = await api.searchAnime(
        query: '',
        genres: genre,
        limit: 20,
      );
      state = state.copyWith(
        genreItems: items,
        isGenreLoading: false,
      );
    } catch (_) {
      state = state.copyWith(isGenreLoading: false);
    }
  }
}

final animeHomeScreenProvider =
    NotifierProvider<AnimeHomeNotifier, AnimeHomeState>(AnimeHomeNotifier.new);

// -------------------------------------------------------------
// Anime Details Provider
// -------------------------------------------------------------

class AnimeDetailsState {
  final AnimeItem? anime;
  final List<AnimeEpisode> episodes;
  final List<Map<String, dynamic>> characters;
  final List<AnimeItem> recommendations;
  final bool isLoading;
  final String? error;

  const AnimeDetailsState({
    this.anime,
    this.episodes = const [],
    this.characters = const [],
    this.recommendations = const [],
    this.isLoading = false,
    this.error,
  });
}

final animeDetailsProvider = FutureProvider.family<AnimeDetailsState, int>((ref, malId) async {
  final api = ref.watch(jikanApiServiceProvider);

  try {
    // 1. Fetch anime details first
    final anime = await api.getAnimeDetails(malId).timeout(
          const Duration(seconds: 4),
          onTimeout: () => null,
        );

    final titleToUse = anime?.displayTitle ?? anime?.title;

    // 2. Fetch episodes, characters, and recommendations concurrently
    final episodesFuture = api.getAnimeEpisodes(
      malId,
      totalCount: anime?.episodes,
      title: titleToUse,
    ).timeout(
      const Duration(seconds: 5),
      onTimeout: () => <AnimeEpisode>[],
    );

    final charactersFuture = api.getAnimeCharacters(malId).timeout(
      const Duration(seconds: 5),
      onTimeout: () => <Map<String, dynamic>>[],
    );

    final recsFuture = api.getAnimeRecommendations(malId).timeout(
      const Duration(seconds: 5),
      onTimeout: () => <AnimeItem>[],
    );

    final results = await Future.wait([episodesFuture, charactersFuture, recsFuture]);
    var episodes = results[0] as List<AnimeEpisode>;
    final characters = results[1] as List<Map<String, dynamic>>;
    final recommendations = results[2] as List<AnimeItem>;

    if (episodes.isEmpty && anime?.episodes != null && anime!.episodes! > 0) {
      episodes = List.generate(
        anime.episodes!,
        (index) => AnimeEpisode.synthetic(
          malId,
          index + 1,
          defaultThumbnail: anime.backdropUrl ?? anime.posterUrl,
        ),
      );
    }

    return AnimeDetailsState(
      anime: anime,
      episodes: episodes,
      characters: characters,
      recommendations: recommendations,
      isLoading: false,
    );
  } catch (e) {
    return AnimeDetailsState(
      error: e.toString(),
      isLoading: false,
    );
  }
});
