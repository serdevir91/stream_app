import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../search/domain/entities/media_item.dart';
import '../../../search/presentation/providers/search_provider.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../data/repositories/library_repository.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository();
});

final libraryChangesProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(libraryRepositoryProvider);
  return repo.watchChanges();
});

class LibraryNotifier extends Notifier<List<MediaItem>> {
  late LibraryRepository _repository;

  @override
  List<MediaItem> build() {
    _repository = ref.watch(libraryRepositoryProvider);
    ref.watch(libraryChangesProvider);
    return _repository.getItems();
  }

  void _reload() {
    state = _repository.getItems();
  }

  bool isInLibrary(String mediaId) {
    return state.any((item) => item.id == mediaId);
  }

  Future<bool> toggle(MediaItem item) async {
    final alreadySaved = _repository.contains(item.id);
    if (alreadySaved) {
      await _repository.remove(item.id);
      _reload();
      return false;
    }

    await _repository.upsert(item);
    _reload();
    return true;
  }

  Future<void> remove(String mediaId) async {
    await _repository.remove(mediaId);
    _reload();
  }
}

final libraryProvider = NotifierProvider<LibraryNotifier, List<MediaItem>>(
  LibraryNotifier.new,
);

class NewEpisodeItem {
  final MediaItem series;
  final LatestEpisodeInfo episode;

  const NewEpisodeItem({required this.series, required this.episode});
}

final sortedLibraryProvider = Provider<List<MediaItem>>((ref) {
  final items = ref.watch(libraryProvider);
  final settings = ref.watch(appSettingsProvider);
  final libraryRepo = ref.watch(libraryRepositoryProvider);
  ref.watch(watchHistoryChangesProvider);
  final historyRepo = ref.watch(watchHistoryRepositoryProvider);
  final allHistory = historyRepo.getAllHistory();

  // Build a map of mediaId -> latest updatedAtMs across all episodes.
  final lastWatchedMap = <String, int>{};
  for (final entry in allHistory) {
    final existing = lastWatchedMap[entry.mediaId];
    if (existing == null || entry.updatedAtMs > existing) {
      lastWatchedMap[entry.mediaId] = entry.updatedAtMs;
    }
  }

  final sorted = List<MediaItem>.from(items);
  sorted.sort((a, b) {
    switch (settings.librarySort) {
      case 'added':
        final aTime = libraryRepo.getUpdatedAtMs(a.id) ?? 0;
        final bTime = libraryRepo.getUpdatedAtMs(b.id) ?? 0;
        return bTime.compareTo(aTime);
      case 'title':
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case 'rating':
        final ratingCompare = (b.rating ?? 0).compareTo(a.rating ?? 0);
        if (ratingCompare != 0) return ratingCompare;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case 'type':
        final typeCompare = a.type.compareTo(b.type);
        if (typeCompare != 0) return typeCompare;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }

    final aTime = lastWatchedMap[a.id];
    final bTime = lastWatchedMap[b.id];
    // Both have watch history: sort by most recent first.
    if (aTime != null && bTime != null) {
      return bTime.compareTo(aTime);
    }
    // Only one has watch history: that one comes first.
    if (aTime != null) return -1;
    if (bTime != null) return 1;
    // Neither has watch history: keep original order.
    return 0;
  });

  return sorted;
});

final newEpisodesProvider = FutureProvider<List<NewEpisodeItem>>((ref) async {
  final settings = ref.watch(appSettingsProvider);
  if (!settings.newEpisodeNotificationsEnabled) {
    return const [];
  }

  final items = ref.watch(libraryProvider);
  ref.watch(watchHistoryChangesProvider);
  final historyRepo = ref.watch(watchHistoryRepositoryProvider);
  final searchRepo = ref.watch(searchRepositoryProvider);
  final results = <NewEpisodeItem>[];

  for (final item in items.where((item) => item.type == 'tv')) {
    final episode = await searchRepo.getLatestEpisodeInfo(item.id);
    if (episode == null || !episode.isRecentlyAired) {
      continue;
    }
    final history = historyRepo.getProgress(
      item.id,
      mediaType: 'tv',
      season: episode.seasonNumber,
      episode: episode.episodeNumber,
    );
    if (history?.isWatched == true) {
      continue;
    }
    results.add(NewEpisodeItem(series: item, episode: episode));
  }

  results.sort((a, b) {
    final aDate = a.episode.airDate ?? '';
    final bDate = b.episode.airDate ?? '';
    return bDate.compareTo(aDate);
  });
  return results;
});
