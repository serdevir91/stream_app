import 'dart:async';

import 'package:hive/hive.dart';
import '../../domain/entities/watch_history.dart';
import '../models/watch_history_model.dart';

class ContinueWatchItem {
  final WatchHistory baseHistory;
  final int targetSeason;
  final int targetEpisode;
  final bool startFromBeginning;

  const ContinueWatchItem({
    required this.baseHistory,
    required this.targetSeason,
    required this.targetEpisode,
    required this.startFromBeginning,
  });
}

class WatchHistoryRepository {
  static const String boxName = 'watch_history_box';
  final StreamController<int> _changesController =
      StreamController<int>.broadcast();
  int _changeVersion = 0;

  Future<void> init() async {
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(WatchHistoryModelAdapter());
    }
    await Hive.openBox<WatchHistoryModel>(boxName);
  }

  Box<WatchHistoryModel>? get _boxOrNull {
    if (!Hive.isBoxOpen(boxName)) {
      return null;
    }
    return Hive.box<WatchHistoryModel>(boxName);
  }

  List<WatchHistory> getHistory() {
    final box = _boxOrNull;
    if (box == null) {
      return [];
    }
    return box.values.toList();
  }

  String _buildHistoryId({
    required String mediaId,
    required String mediaType,
    required int season,
    required int episode,
  }) {
    if (mediaType == 'tv') {
      return 'tv_${mediaId}_s${season}_e$episode';
    }
    return 'movie_$mediaId';
  }

  Future<void> saveProgress(WatchHistory history) async {
    final historyId = history.historyId.isNotEmpty
        ? history.historyId
        : _buildHistoryId(
            mediaId: history.mediaId,
            mediaType: history.mediaType,
            season: history.season,
            episode: history.episode,
          );

    final model = WatchHistoryModel(
      historyId: historyId,
      mediaId: history.mediaId,
      title: history.title,
      mediaType: history.mediaType,
      season: history.season,
      episode: history.episode,
      posterUrl: history.posterUrl,
      backdropUrl: history.backdropUrl,
      lastPosition: history.lastPosition,
      duration: history.duration,
      isWatched: history.isWatched,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final box = _boxOrNull ?? await Hive.openBox<WatchHistoryModel>(boxName);
    await box.put(historyId, model);
    _emitChange();
  }

  WatchHistory? getProgress(
    String mediaId, {
    String mediaType = 'movie',
    int season = 1,
    int episode = 1,
  }) {
    final key = _buildHistoryId(
      mediaId: mediaId,
      mediaType: mediaType,
      season: season,
      episode: episode,
    );
    return _boxOrNull?.get(key);
  }

  List<WatchHistory> getAllHistory() {
    final box = _boxOrNull;
    if (box == null) {
      return [];
    }

    final items = box.values.toList().cast<WatchHistory>();
    items.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return items;
  }

  List<ContinueWatchItem> getContinueWatchingItems() {
    final all = getAllHistory();
    final latestByMediaId = <String, WatchHistory>{};

    for (final item in all) {
      final existing = latestByMediaId[item.mediaId];
      if (existing == null || item.updatedAtMs > existing.updatedAtMs) {
        latestByMediaId[item.mediaId] = item;
      }
    }

    final result = <ContinueWatchItem>[];
    for (final entry in latestByMediaId.values) {
      if (entry.mediaType == 'movie') {
        if (entry.isWatched) {
          continue;
        }
        result.add(
          ContinueWatchItem(
            baseHistory: entry,
            targetSeason: 1,
            targetEpisode: 1,
            startFromBeginning: false,
          ),
        );
        continue;
      }

      if (entry.isWatched) {
        result.add(
          ContinueWatchItem(
            baseHistory: entry,
            targetSeason: entry.season,
            targetEpisode: entry.episode + 1,
            startFromBeginning: true,
          ),
        );
      } else {
        result.add(
          ContinueWatchItem(
            baseHistory: entry,
            targetSeason: entry.season,
            targetEpisode: entry.episode,
            startFromBeginning: false,
          ),
        );
      }
    }

    result.sort(
      (a, b) => b.baseHistory.updatedAtMs.compareTo(a.baseHistory.updatedAtMs),
    );
    return result;
  }

  Stream<int> watchChanges() {
    return Stream<int>.multi((controller) {
      controller.add(_changeVersion);
      final sub = _changesController.stream.listen(
        controller.add,
        onError: controller.addError,
      );
      controller.onCancel = sub.cancel;
    });
  }

  Future<void> deleteProgress(String mediaId) async {
    final movieKey = 'movie_$mediaId';
    final tvPrefix = 'tv_${mediaId}_';
    final box = _boxOrNull;
    if (box == null) {
      return;
    }
    final keys = box.keys.where((k) {
      final key = k.toString();
      return key == movieKey || key.startsWith(tvPrefix);
    }).toList();
    for (final key in keys) {
      await box.delete(key);
    }
    if (keys.isNotEmpty) {
      _emitChange();
    }
  }

  void _emitChange() {
    if (_changesController.isClosed) {
      return;
    }
    _changeVersion += 1;
    _changesController.add(_changeVersion);
  }
}
