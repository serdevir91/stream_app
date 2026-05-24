import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../search/domain/entities/media_item.dart';
import '../../../search/presentation/providers/search_provider.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/domain/entities/watch_history.dart';
import '../../data/repositories/watched_repository.dart';
import 'library_provider.dart';

final watchedRepositoryProvider = Provider<WatchedRepository>((ref) {
  return WatchedRepository();
});

final watchedChangesProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(watchedRepositoryProvider);
  return repo.watchChanges();
});

class WatchedNotifier extends Notifier<List<MediaItem>> {
  late WatchedRepository _repository;

  @override
  List<MediaItem> build() {
    _repository = ref.watch(watchedRepositoryProvider);
    ref.watch(watchedChangesProvider);

    // Watch history changes to auto-add watched items
    final historyEntries = ref.watch(watchHistoryEntriesProvider);
    _syncFromWatchHistory(historyEntries);

    return _repository.getItems();
  }

  void _reload() {
    state = _repository.getItems();
  }

  Future<void> checkTvShowCompletion(String seriesId) async {
    try {
      final seasons = await ref.read(seriesSeasonsProvider(seriesId).future);
      if (seasons.isEmpty) return;

      final totalEpisodes = seasons.fold<int>(0, (sum, s) => sum + s.episodeCount);
      if (totalEpisodes <= 0) return;

      final historyRepo = ref.read(watchHistoryRepositoryProvider);
      final allHistory = historyRepo.getAllHistory();

      final watchedEpisodeKeys = allHistory
          .where((h) =>
              h.mediaId == seriesId &&
              h.mediaType == 'tv' &&
              h.isWatched)
          .map((h) => '${h.season}_${h.episode}')
          .toSet();

      if (watchedEpisodeKeys.length >= totalEpisodes) {
        // All episodes are watched!
        // 1. Remove from library
        await ref.read(libraryProvider.notifier).remove(seriesId);

        // 2. Mark the series itself as watched (add to watched box)
        if (!_repository.contains(seriesId)) {
          final libItem = ref.read(libraryProvider).firstWhere(
                (item) => item.id == seriesId,
                orElse: () => MediaItem(id: seriesId, title: '', type: 'tv'),
              );
          
          final title = libItem.title.isNotEmpty
              ? libItem.title
              : allHistory.firstWhere((h) => h.mediaId == seriesId).title;
          final posterUrl = libItem.posterUrl ??
              allHistory.firstWhere((h) => h.mediaId == seriesId, orElse: () => WatchHistory(mediaId: seriesId, title: '', lastPosition: 0, duration: 0)).posterUrl;
          final backdropUrl = libItem.backdropUrl ??
              allHistory.firstWhere((h) => h.mediaId == seriesId, orElse: () => WatchHistory(mediaId: seriesId, title: '', lastPosition: 0, duration: 0)).backdropUrl;

          final seriesItem = MediaItem(
            id: seriesId,
            title: title,
            type: 'tv',
            posterUrl: posterUrl,
            backdropUrl: backdropUrl,
          );

          await _repository.upsert(seriesItem);
          _reload();
        }
      }
    } catch (e) {
      debugPrint('Error checking TV show completion: $e');
    }
  }

  void _syncFromWatchHistory(List<WatchHistory> historyEntries) {
    for (final entry in historyEntries) {
      if (entry.isWatched) {
        if (entry.mediaType == 'movie') {
          if (!_repository.contains(entry.mediaId)) {
            final item = MediaItem(
              id: entry.mediaId,
              title: entry.title,
              type: entry.mediaType,
              posterUrl: entry.posterUrl,
              backdropUrl: entry.backdropUrl,
            );
            Future.microtask(() async {
              await _repository.upsert(item);
              await ref.read(libraryProvider.notifier).remove(entry.mediaId);
              _reload();
            });
          }
        } else if (entry.mediaType == 'tv') {
          Future.microtask(() async {
            await checkTvShowCompletion(entry.mediaId);
          });
        }
      }
    }
  }

  bool isWatched(String mediaId) {
    return state.any((item) => item.id == mediaId);
  }

  Future<bool> toggle(MediaItem item) async {
    final alreadyWatched = _repository.contains(item.id);
    if (alreadyWatched) {
      await _repository.remove(item.id);
      // Also delete progress from watch history to prevent immediate auto-add
      await ref.read(watchHistoryRepositoryProvider).deleteProgress(item.id);
      _reload();
      return false;
    }

    await _repository.upsert(item);
    // Remove from library (my list) when marked as watched!
    await ref.read(libraryProvider.notifier).remove(item.id);
    _reload();
    return true;
  }

  Future<void> remove(String mediaId) async {
    await _repository.remove(mediaId);
    // Also delete progress from watch history to prevent immediate auto-add
    await ref.read(watchHistoryRepositoryProvider).deleteProgress(mediaId);
    _reload();
  }
}

final watchedProvider = NotifierProvider<WatchedNotifier, List<MediaItem>>(
  WatchedNotifier.new,
);

final sortedWatchedProvider = Provider<List<MediaItem>>((ref) {
  final items = ref.watch(watchedProvider);
  final settings = ref.watch(appSettingsProvider);
  final watchedRepo = ref.watch(watchedRepositoryProvider);

  final sorted = List<MediaItem>.from(items);
  sorted.sort((a, b) {
    switch (settings.librarySort) {
      case 'added':
        final aTime = watchedRepo.getUpdatedAtMs(a.id) ?? 0;
        final bTime = watchedRepo.getUpdatedAtMs(b.id) ?? 0;
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
    // Default to added date descending
    final aTime = watchedRepo.getUpdatedAtMs(a.id) ?? 0;
    final bTime = watchedRepo.getUpdatedAtMs(b.id) ?? 0;
    return bTime.compareTo(aTime);
  });

  return sorted;
});
