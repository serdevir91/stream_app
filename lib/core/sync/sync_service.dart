import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'device_identity.dart';
import 'sync_repository.dart';
import '../../features/library/data/repositories/library_repository.dart';
import '../../features/player/domain/entities/watch_history.dart';
import '../../features/player/data/repositories/watch_history_repository.dart';

class SyncService {
  static const String _syncMetaBox = 'sync_meta_box';
  static const String _lastSyncKey = 'last_sync_ms';
  static const String _watchSnapshotKey = 'watch_snapshot_ids';
  static const String _librarySnapshotKey = 'library_snapshot_ids';
  static const String _watchDeletePrefix = 'wh:';
  static const String _libraryDeletePrefix = 'lib:';

  SyncRepository? _repo;
  Timer? _periodicTimer;
  Timer? _debounceTimer;
  bool _isSyncing = false;
  String? _lastRegisterError;

  final WatchHistoryRepository _watchHistoryRepo;
  final LibraryRepository _libraryRepo;

  SyncService(this._watchHistoryRepo, this._libraryRepo);

  String? get lastRegisterError => _lastRegisterError;

  Future<void> init({String? serverUrl}) async {
    final isRegistered = await DeviceIdentity.isRegistered();
    if (!isRegistered) return;

    final resolvedServerUrl = serverUrl ?? await DeviceIdentity.getServerUrl();
    if (resolvedServerUrl == null || resolvedServerUrl.isEmpty) return;

    final token = await DeviceIdentity.getAuthToken();
    _repo = SyncRepository(baseUrl: resolvedServerUrl, authToken: token);

    // Start periodic sync every 15 minutes.
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => syncNow(),
    );
  }

  Future<bool> register({
    required String serverUrl,
    required String deviceName,
    required String tmdbAccessToken,
  }) async {
    final deviceId = await DeviceIdentity.getOrCreateDeviceId();
    _lastRegisterError = null;
    final normalizedToken = tmdbAccessToken.trim();
    if (normalizedToken.isEmpty) {
      _lastRegisterError = 'TMDB token bos olamaz.';
      return false;
    }

    final candidates = _buildServerCandidates(serverUrl);
    if (candidates.isEmpty) {
      _lastRegisterError = 'Gecersiz sunucu adresi: "$serverUrl"';
      return false;
    }

    for (final candidate in candidates) {
      final repo = SyncRepository(baseUrl: candidate);
      try {
        final result = await repo.registerDevice(
          deviceId: deviceId,
          deviceName: deviceName,
          tmdbAccessToken: normalizedToken,
        );
        final token = result['auth_token'] as String?;
        if (token == null || token.isEmpty) {
          _lastRegisterError = 'Sunucu auth token donmedi [$candidate]';
          continue;
        }

        await DeviceIdentity.saveAuthToken(token);
        await DeviceIdentity.saveServerUrl(candidate);
        _repo = SyncRepository(baseUrl: candidate, authToken: token);
        _startPeriodicSync();
        return true;
      } catch (e) {
        _lastRegisterError = e.toString();
        debugPrint('Device registration failed on $candidate: $e');
      }
    }

    return false;
  }

  Future<void> syncNow() async {
    if (_isSyncing || _repo == null) return;
    _isSyncing = true;

    try {
      final deviceId = await DeviceIdentity.getOrCreateDeviceId();
      final lastSyncMs = await _getLastSyncMs();

      // Push local changes.
      await _pushLocalChanges(deviceId, lastSyncMs);

      // Pull remote changes.
      await _pullRemoteChanges(deviceId, lastSyncMs);

      await _updateSnapshots();

      await _setLastSyncMs(DateTime.now().millisecondsSinceEpoch);
      debugPrint('Sync completed successfully');
    } catch (e) {
      debugPrint('Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }

  void syncDebounced() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 30), () => syncNow());
  }

  Future<void> _pushLocalChanges(String deviceId, int sinceMs) async {
    final allHistory = _watchHistoryRepo.getAllHistory();
    final watchHistoryMaps = allHistory
        .where((h) => h.updatedAtMs > sinceMs)
        .map(
          (h) => {
            'history_id': h.historyId,
            'media_id': h.mediaId,
            'title': h.title,
            'media_type': h.mediaType,
            'season': h.season,
            'episode': h.episode,
            'poster_url': h.posterUrl,
            'backdrop_url': h.backdropUrl,
            'source_id': h.sourceId,
            'last_position': h.lastPosition,
            'duration': h.duration,
            'is_watched': h.isWatched,
            'updated_at_ms': h.updatedAtMs,
          },
        )
        .toList();
    final libraryMaps = _libraryRepo
        .getSyncEntries()
        .where((item) => (item['updated_at_ms'] as int? ?? 0) > sinceMs)
        .toList();
    final deletedIds = await _collectDeletedIds(
      allHistory: allHistory,
      currentLibraryIds: _libraryRepo.getItemIds(),
    );

    if (watchHistoryMaps.isEmpty && libraryMaps.isEmpty && deletedIds.isEmpty) {
      return;
    }

    await _repo!.pushChanges(
      deviceId: deviceId,
      watchHistory: watchHistoryMaps,
      library: libraryMaps,
      deletedIds: deletedIds,
      sinceMs: sinceMs,
    );
    await _updateSnapshots();
  }

  Future<void> _pullRemoteChanges(String deviceId, int sinceMs) async {
    final result = await _repo!.pullChanges(
      deviceId: deviceId,
      sinceMs: sinceMs,
    );

    final remoteHistory = result['watch_history'] as List<dynamic>? ?? [];
    for (final item in remoteHistory) {
      final map = item as Map<String, dynamic>;
      final localEntry = _watchHistoryRepo.getProgress(
        map['media_id'] as String,
        mediaType: map['media_type'] as String? ?? 'movie',
        season: map['season'] as int? ?? 1,
        episode: map['episode'] as int? ?? 1,
      );

      // Only apply if remote is newer.
      final remoteUpdatedAt = map['updated_at_ms'] as int? ?? 0;
      if (localEntry != null && localEntry.updatedAtMs >= remoteUpdatedAt) {
        continue;
      }

      await _watchHistoryRepo.saveProgress(
        WatchHistory(
          historyId: map['history_id'] as String? ?? '',
          mediaId: map['media_id'] as String,
          title: map['title'] as String? ?? '',
          mediaType: map['media_type'] as String? ?? 'movie',
          season: map['season'] as int? ?? 1,
          episode: map['episode'] as int? ?? 1,
          posterUrl: map['poster_url'] as String?,
          backdropUrl: map['backdrop_url'] as String?,
          sourceId: map['source_id'] as String?,
          lastPosition: map['last_position'] as int? ?? 0,
          duration: map['duration'] as int? ?? 0,
          isWatched: map['is_watched'] as bool? ?? false,
          updatedAtMs: remoteUpdatedAt,
        ),
        useProvidedUpdatedAt: true,
      );
    }

    final remoteLibrary = result['library'] as List<dynamic>? ?? [];
    for (final item in remoteLibrary) {
      final map = item as Map<String, dynamic>;
      final mediaId = map['media_id'] as String? ?? '';
      if (mediaId.isEmpty) {
        continue;
      }
      final remoteUpdatedAt = map['updated_at_ms'] as int? ?? 0;
      final localUpdatedAt = _libraryRepo.getUpdatedAtMs(mediaId) ?? 0;
      if (localUpdatedAt >= remoteUpdatedAt) {
        continue;
      }

      await _libraryRepo.upsertFromSync(
        mediaId: mediaId,
        title: map['title'] as String? ?? '',
        mediaType: map['media_type'] as String? ?? 'movie',
        posterUrl: map['poster_url'] as String?,
        updatedAtMs: remoteUpdatedAt,
      );
    }

    final deletedIds = result['deleted_ids'] as List<dynamic>? ?? [];
    for (final raw in deletedIds) {
      final deleteId = raw.toString();
      if (deleteId.startsWith(_watchDeletePrefix)) {
        final historyId = deleteId.substring(_watchDeletePrefix.length);
        if (historyId.isNotEmpty) {
          await _watchHistoryRepo.deleteByHistoryId(historyId);
        }
      } else if (deleteId.startsWith(_libraryDeletePrefix)) {
        final mediaId = deleteId.substring(_libraryDeletePrefix.length);
        if (mediaId.isNotEmpty) {
          await _libraryRepo.remove(mediaId);
        }
      }
    }
  }

  Future<int> _getLastSyncMs() async {
    if (!Hive.isBoxOpen(_syncMetaBox)) {
      await Hive.openBox(_syncMetaBox);
    }
    return (Hive.box(_syncMetaBox).get(_lastSyncKey) as int?) ?? 0;
  }

  Future<void> _setLastSyncMs(int ms) async {
    if (!Hive.isBoxOpen(_syncMetaBox)) {
      await Hive.openBox(_syncMetaBox);
    }
    await Hive.box(_syncMetaBox).put(_lastSyncKey, ms);
  }

  Future<int> getLastSyncTimestamp() => _getLastSyncMs();

  Future<List<String>> _collectDeletedIds({
    required List<WatchHistory> allHistory,
    required Set<String> currentLibraryIds,
  }) async {
    final box = await _openMetaBox();

    final previousWatchIds = _readStringList(box, _watchSnapshotKey).toSet();
    final previousLibraryIds = _readStringList(
      box,
      _librarySnapshotKey,
    ).toSet();

    final currentWatchIds = allHistory
        .map((h) => h.historyId)
        .where((id) => id.isNotEmpty)
        .toSet();

    final deletedWatch = previousWatchIds
        .difference(currentWatchIds)
        .map((id) => '$_watchDeletePrefix$id');
    final deletedLibrary = previousLibraryIds
        .difference(currentLibraryIds)
        .map((id) => '$_libraryDeletePrefix$id');

    return [...deletedWatch, ...deletedLibrary];
  }

  Future<void> _updateSnapshots() async {
    final box = await _openMetaBox();
    final watchIds = _watchHistoryRepo
        .getAllHistory()
        .map((h) => h.historyId)
        .where((id) => id.isNotEmpty)
        .toList();
    final libraryIds = _libraryRepo.getItemIds().toList();

    await box.put(_watchSnapshotKey, watchIds);
    await box.put(_librarySnapshotKey, libraryIds);
  }

  Future<Box<dynamic>> _openMetaBox() async {
    if (!Hive.isBoxOpen(_syncMetaBox)) {
      return Hive.openBox<dynamic>(_syncMetaBox);
    }
    return Hive.box<dynamic>(_syncMetaBox);
  }

  List<String> _readStringList(Box<dynamic> box, String key) {
    final raw = box.get(key);
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return const [];
  }

  void dispose() {
    _periodicTimer?.cancel();
    _debounceTimer?.cancel();
  }

  void _startPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => syncNow(),
    );
  }

  List<String> _buildServerCandidates(String input) {
    final normalized = _normalizeServerUrl(input);
    if (normalized == null) return const [];

    final parsed = Uri.tryParse(normalized);
    if (parsed == null || parsed.host.isEmpty) return const [];

    final candidates = <String>[normalized];
    final altPort = parsed.port == 8000
        ? 8080
        : parsed.port == 8080
        ? 8000
        : null;

    if (altPort != null) {
      final alt = parsed.replace(port: altPort).toString();
      if (!candidates.contains(alt)) {
        candidates.add(alt);
      }
    }

    return candidates;
  }

  String? _normalizeServerUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) return null;

    if (!value.contains('://')) {
      value = 'http://$value';
    }

    final parsed = Uri.tryParse(value);
    if (parsed == null || parsed.host.isEmpty) return null;

    final withDefaultPort = parsed.hasPort
        ? parsed
        : parsed.replace(port: 8000);

    final normalized = withDefaultPort.toString();
    if (normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}
