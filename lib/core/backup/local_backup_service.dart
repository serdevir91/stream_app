import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

import '../../features/library/data/repositories/library_repository.dart';
import '../../features/library/data/repositories/watched_repository.dart';
import '../../features/player/data/models/watch_history_model.dart';
import '../../features/player/data/repositories/watch_history_repository.dart';
import '../../features/sources/data/models/source_model.dart';
import '../../features/sources/data/repositories/sources_repository.dart';
import '../settings/app_settings.dart';
import '../settings/app_settings_repository.dart';

class LocalBackupException implements Exception {
  final String message;

  const LocalBackupException(this.message);

  @override
  String toString() => message;
}

class LocalBackupRestoreResult {
  final int sourceCount;
  final int watchHistoryCount;
  final int libraryCount;
  final int watchedCount;

  const LocalBackupRestoreResult({
    required this.sourceCount,
    required this.watchHistoryCount,
    required this.libraryCount,
    required this.watchedCount,
  });
}

class LocalBackupService {
  static const int _backupVersion = 1;
  static const String _backupType = 'stream_app_local_backup';
  static const String _addonConfigBoxName = 'addon_config_box';
  static const String _syncMetaBoxName = 'sync_meta_box';

  static Future<String> exportToPath(String outputPath) async {
    final payload = await _buildPayload();
    final file = File(outputPath);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    return file.path;
  }

  static Future<LocalBackupRestoreResult> importFromPath(
    String filePath,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const LocalBackupException('backup_file_not_found');
    }

    final content = await file.readAsString();
    final raw = jsonDecode(content);
    if (raw is! Map) {
      throw const LocalBackupException('backup_format_invalid');
    }

    final payload = Map<String, dynamic>.from(raw);
    final type = payload['type']?.toString() ?? '';
    if (type != _backupType) {
      throw const LocalBackupException('not_stream_app_backup');
    }

    final version = payload['version'];
    if (version is! int || version > _backupVersion) {
      throw const LocalBackupException('backup_version_not_supported');
    }

    return _applyPayload(payload);
  }

  static Future<Map<String, dynamic>> _buildPayload() async {
    final settingsBox = await _openOrCreateBox<dynamic>(
      AppSettingsRepository.boxName,
    );
    final settingsRaw = settingsBox.get(AppSettingsRepository.key);
    final settingsMap = settingsRaw is Map
        ? AppSettings.fromMap(settingsRaw).toMap()
        : AppSettings.defaults.toMap();

    final sourcesBox = await _openOrCreateBox<SourceModel>(
      SourcesRepository.boxName,
    );
    final sources = sourcesBox.values
        .map(
          (s) => {
            'id': s.id,
            'name': s.name,
            'base_url': s.baseUrl,
            'search_endpoint': s.searchEndpoint,
            'is_enabled': s.isEnabled,
          },
        )
        .toList();

    final watchHistoryBox = await _openOrCreateBox<WatchHistoryModel>(
      WatchHistoryRepository.boxName,
    );
    final watchHistory = watchHistoryBox.values
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

    final libraryBox = await _openOrCreateBox<dynamic>(
      LibraryRepository.boxName,
    );
    final library = libraryBox.values
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final watchedBox = await _openOrCreateBox<dynamic>(
      WatchedRepository.boxName,
    );
    final watched = watchedBox.values
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final addonConfigBox = await _openOrCreateBox<dynamic>(_addonConfigBoxName);
    final addonConfig = <String, dynamic>{
      'enabled': _readStringBoolMap(addonConfigBox.get('enabled')),
      'custom_urls': _readStringMap(addonConfigBox.get('custom_urls')),
      'custom_manifests': _readNestedMap(
        addonConfigBox.get('custom_manifests'),
      ),
      'removed_builtins': _readStringList(
        addonConfigBox.get('removed_builtins'),
      ),
    };

    return {
      'type': _backupType,
      'version': _backupVersion,
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
      'app_settings': settingsMap,
      'sources': sources,
      'watch_history': watchHistory,
      'library': library,
      'watched': watched,
      'addon_config': addonConfig,
    };
  }

  static Future<LocalBackupRestoreResult> _applyPayload(
    Map<String, dynamic> payload,
  ) async {
    final settingsBox = await _openOrCreateBox<dynamic>(
      AppSettingsRepository.boxName,
    );
    final rawSettings = payload['app_settings'];
    if (rawSettings is Map) {
      final normalized = AppSettings.fromMap(rawSettings).toMap();
      await settingsBox.put(AppSettingsRepository.key, normalized);
    }

    final sourcesBox = await _openOrCreateBox<SourceModel>(
      SourcesRepository.boxName,
    );
    await sourcesBox.clear();
    final sources = payload['sources'] is List
        ? payload['sources'] as List
        : [];
    for (final item in sources.whereType<Map>()) {
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      await sourcesBox.put(
        id,
        SourceModel(
          id: id,
          name: item['name']?.toString() ?? 'Custom Source',
          baseUrl: item['base_url']?.toString() ?? '',
          searchEndpoint: item['search_endpoint']?.toString() ?? '',
          isEnabled: item['is_enabled'] == true,
        ),
      );
    }

    final watchHistoryBox = await _openOrCreateBox<WatchHistoryModel>(
      WatchHistoryRepository.boxName,
    );
    await watchHistoryBox.clear();
    final history = payload['watch_history'] is List
        ? payload['watch_history'] as List
        : [];
    for (final item in history.whereType<Map>()) {
      final mediaId = item['media_id']?.toString() ?? '';
      if (mediaId.isEmpty) continue;
      final mediaType = item['media_type']?.toString() ?? 'movie';
      final season = item['season'] is int ? item['season'] as int : 1;
      final episode = item['episode'] is int ? item['episode'] as int : 1;
      final fallbackHistoryId = mediaType == 'tv'
          ? 'tv_${mediaId}_s${season}_e$episode'
          : 'movie_$mediaId';
      final historyId = item['history_id']?.toString() ?? fallbackHistoryId;
      await watchHistoryBox.put(
        historyId,
        WatchHistoryModel(
          historyId: historyId,
          mediaId: mediaId,
          title: item['title']?.toString() ?? '',
          mediaType: mediaType,
          season: season,
          episode: episode,
          posterUrl: item['poster_url']?.toString(),
          backdropUrl: item['backdrop_url']?.toString(),
          sourceId: item['source_id']?.toString(),
          lastPosition: item['last_position'] is int
              ? item['last_position'] as int
              : 0,
          duration: item['duration'] is int ? item['duration'] as int : 0,
          isWatched: item['is_watched'] == true,
          updatedAtMs: item['updated_at_ms'] is int
              ? item['updated_at_ms'] as int
              : DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    final libraryBox = await _openOrCreateBox<dynamic>(
      LibraryRepository.boxName,
    );
    await libraryBox.clear();
    final library = payload['library'] is List
        ? payload['library'] as List
        : [];
    for (final item in library.whereType<Map>()) {
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      await libraryBox.put(id, Map<String, dynamic>.from(item));
    }

    final watchedBox = await _openOrCreateBox<dynamic>(
      WatchedRepository.boxName,
    );
    await watchedBox.clear();
    final watched = payload['watched'] is List
        ? payload['watched'] as List
        : [];
    for (final item in watched.whereType<Map>()) {
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      await watchedBox.put(id, Map<String, dynamic>.from(item));
    }

    final addonConfigBox = await _openOrCreateBox<dynamic>(_addonConfigBoxName);
    await addonConfigBox.clear();
    final addonRaw = payload['addon_config'];
    if (addonRaw is Map) {
      await addonConfigBox.put(
        'enabled',
        _readStringBoolMap(addonRaw['enabled']),
      );
      await addonConfigBox.put(
        'custom_urls',
        _readStringMap(addonRaw['custom_urls']),
      );
      await addonConfigBox.put(
        'custom_manifests',
        _readNestedMap(addonRaw['custom_manifests']),
      );
      await addonConfigBox.put(
        'removed_builtins',
        _readStringList(addonRaw['removed_builtins']),
      );
    }

    // Force a clean sync baseline after restore.
    final syncMetaBox = await _openOrCreateBox<dynamic>(_syncMetaBoxName);
    await syncMetaBox.clear();

    return LocalBackupRestoreResult(
      sourceCount: sourcesBox.length,
      watchHistoryCount: watchHistoryBox.length,
      libraryCount: libraryBox.length,
      watchedCount: watchedBox.length,
    );
  }

  static Future<Box<T>> _openOrCreateBox<T>(String boxName) async {
    if (Hive.isBoxOpen(boxName)) {
      return Hive.box<T>(boxName);
    }
    return Hive.openBox<T>(boxName);
  }

  static Map<String, bool> _readStringBoolMap(dynamic value) {
    if (value is! Map) return {};
    return value.map((key, raw) => MapEntry(key.toString(), raw == true));
  }

  static Map<String, String> _readStringMap(dynamic value) {
    if (value is! Map) return {};
    return value.map((key, raw) => MapEntry(key.toString(), raw.toString()));
  }

  static Map<String, Map<String, dynamic>> _readNestedMap(dynamic value) {
    if (value is! Map) return {};
    return value.map((key, raw) {
      if (raw is Map) {
        return MapEntry(key.toString(), Map<String, dynamic>.from(raw));
      }
      return MapEntry(key.toString(), <String, dynamic>{});
    });
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) return const [];
    return value.map((e) => e.toString()).toList();
  }
}
