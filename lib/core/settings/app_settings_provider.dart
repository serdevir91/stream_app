import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings.dart';
import 'app_settings_repository.dart';

enum TmdbSyncStatus { synced, skipped, failed }

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>((ref) {
  return AppSettingsRepository();
});

class AppSettingsNotifier extends Notifier<AppSettings> {
  late AppSettingsRepository _repository;

  @override
  AppSettings build() {
    _repository = ref.watch(appSettingsRepositoryProvider);
    return _repository.getSettings();
  }

  Future<TmdbSyncStatus> saveSettings(AppSettings next) async {
    state = next;
    await _repository.saveSettings(next);
    return _syncTmdbToken(next.tmdbAccessToken);
  }

  Future<TmdbSyncStatus> _syncTmdbToken(String token) async {
    final trimmedToken = token.trim();

    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://127.0.0.1:8000',
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      try {
        final health = await dio.get('/api/health');
        if (health.statusCode != 200) {
          return TmdbSyncStatus.skipped;
        }
      } catch (_) {
        return TmdbSyncStatus.skipped;
      }

      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final response = await dio.post(
            '/api/settings/tmdb',
            data: {'tmdb_access_token': trimmedToken},
          );
          if (response.statusCode == 200 && response.data['success'] == true) {
            return TmdbSyncStatus.synced;
          }
        } catch (_) {
          if (attempt < 2) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            continue;
          }
        }
      }
      return TmdbSyncStatus.failed;
    } catch (_) {
      return TmdbSyncStatus.failed;
    }
  }
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
