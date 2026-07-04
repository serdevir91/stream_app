import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/settings/app_settings_provider.dart';
import '../../../../core/subtitles/online_subtitle_repository.dart';
import '../../domain/entities/watch_history.dart';
import '../../data/repositories/watch_history_repository.dart';
import '../../../search/presentation/providers/search_provider.dart';
import '../../../search/domain/entities/media_item.dart';

final watchHistoryRepositoryProvider = Provider<WatchHistoryRepository>((ref) {
  return WatchHistoryRepository();
});

final onlineSubtitleRepositoryProvider = Provider<OnlineSubtitleRepository>((
  ref,
) {
  final settings = ref.watch(appSettingsProvider);
  return OnlineSubtitleRepository(
    Dio(),
    tmdbAccessToken: settings.tmdbAccessToken,
    wyzieApiKey: settings.wyzieApiKey,
  );
});

final watchHistoryChangesProvider = StreamProvider<int>((ref) {
  final repo = ref.watch(watchHistoryRepositoryProvider);
  return repo.watchChanges();
});

final continueWatchingProvider = FutureProvider<List<ContinueWatchItem>>((ref) async {
  ref.watch(watchHistoryChangesProvider);
  final repo = ref.watch(watchHistoryRepositoryProvider);
  final items = repo.getContinueWatchingItems();

  final searchRepo = ref.watch(searchRepositoryProvider);
  final filteredItems = <ContinueWatchItem>[];

  for (final item in items) {
    if (item.baseHistory.mediaType != 'tv') {
      filteredItems.add(item);
      continue;
    }

    if (!item.startFromBeginning) {
      filteredItems.add(item);
      continue;
    }

    // We want to advance to the next episode, check if it has aired!
    try {
      final episodes = await searchRepo.getSeasonEpisodes(
        item.baseHistory.mediaId,
        item.targetSeason,
      );
      final nextEp = episodes.firstWhere(
        (e) => e.episodeNumber == item.targetEpisode,
        orElse: () => Episode(episodeNumber: -1, name: '', airDate: '9999-12-31'),
      );

      if (nextEp.episodeNumber != -1) {
        if (nextEp.isAired) {
          filteredItems.add(item);
        }
      } else {
        // Episode not found in this season, check if we can roll over to the next season
        final seasons = await searchRepo.getSeriesSeasons(item.baseHistory.mediaId);
        final currentSeasonIndex = seasons.indexWhere((s) => s.seasonNumber == item.targetSeason);
        if (currentSeasonIndex != -1 && currentSeasonIndex + 1 < seasons.length) {
          final nextSeason = seasons[currentSeasonIndex + 1];
          final nextSeasonEpisodes = await searchRepo.getSeasonEpisodes(
            item.baseHistory.mediaId,
            nextSeason.seasonNumber,
          );
          final firstEp = nextSeasonEpisodes.firstWhere(
            (e) => e.episodeNumber == 1,
            orElse: () => Episode(episodeNumber: -1, name: '', airDate: '9999-12-31'),
          );
          if (firstEp.episodeNumber != -1 && firstEp.isAired) {
            filteredItems.add(item);
          }
        }
      }
    } catch (_) {
      // In case of any network error or exception, keep it so it doesn't disappear when offline
      filteredItems.add(item);
    }
  }

  return filteredItems;
});

final watchHistoryEntriesProvider = Provider<List<WatchHistory>>((ref) {
  ref.watch(watchHistoryChangesProvider);
  final repo = ref.watch(watchHistoryRepositoryProvider);
  return repo.getAllHistory();
});
