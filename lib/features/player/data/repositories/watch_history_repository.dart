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
    final normalizedMediaType = _normalizeMediaType(mediaType);
    if (normalizedMediaType == 'tv') {
      return 'tv_${mediaId}_s${season}_e$episode';
    }
    return 'movie_$mediaId';
  }

  String _normalizeMediaType(String mediaType) {
    final normalized = mediaType.trim().toLowerCase();
    if (normalized == 'tv' || normalized == 'series' || normalized == 'show') {
      return 'tv';
    }
    return 'movie';
  }

  Future<void> saveProgress(WatchHistory history) async {
    final normalizedMediaType = _normalizeMediaType(history.mediaType);
    final historyId = history.historyId.isNotEmpty
        ? history.historyId
        : _buildHistoryId(
            mediaId: history.mediaId,
            mediaType: normalizedMediaType,
            season: history.season,
            episode: history.episode,
          );

    final model = WatchHistoryModel(
      historyId: historyId,
      mediaId: history.mediaId,
      title: history.title,
      mediaType: normalizedMediaType,
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
      final normalizedType = _normalizeMediaType(item.mediaType);
      final groupingKey = '${normalizedType}_${item.mediaId}';
      final existing = latestByMediaId[groupingKey];
      if (existing == null || item.updatedAtMs > existing.updatedAtMs) {
        latestByMediaId[groupingKey] = item;
      }
    }

    final result = <ContinueWatchItem>[];
    for (final entry in latestByMediaId.values) {
      final normalizedType = _normalizeMediaType(entry.mediaType);
      if (normalizedType == 'movie') {
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
