import 'package:hive/hive.dart';

import 'app_settings.dart';

class AppSettingsRepository {
  static const String boxName = 'app_settings_box';
  static const String key = 'app_settings';

  Future<void> init() async {
    await Hive.openBox<dynamic>(boxName);
  }

  Box<dynamic>? get _boxOrNull {
    if (!Hive.isBoxOpen(boxName)) {
      return null;
    }
    return Hive.box<dynamic>(boxName);
  }

  AppSettings getSettings() {
    final box = _boxOrNull;
    if (box == null) {
      return AppSettings.defaults;
    }

    final raw = box.get(key);
    if (raw is Map) {
      final schemaVersion = raw['schemaVersion'] is int
          ? raw['schemaVersion'] as int
          : 0;

      if (schemaVersion < 2) {
        final migrated = AppSettings(
          appLanguage: 'en',
          subtitleLanguage: 'en',
          tmdbAccessToken: (raw['tmdbAccessToken'] ?? '').toString(),
          wyzieApiKey: (raw['wyzieApiKey'] ?? '').toString(),
          backendUrl: 'http://127.0.0.1:8000',
          autoSelectSource: true,
          preferredSourceId: '',
          videoPlayer: 'native',
          autoSelectSubtitle: false,
          librarySort: 'recent',
          watchHistoryEnabled: true,
          newEpisodeNotificationsEnabled: true,
          completionPercentage: 90,
          homeCategories: defaultHomeCategories,
        );
        box.put(key, migrated.toMap());
        return migrated;
      }

      var parsed = AppSettings.fromMap(raw);
      if (schemaVersion < 10) {
        final current = List<String>.from(parsed.homeCategories);
        for (final cat in defaultHomeCategories) {
          if (!current.contains(cat)) {
            current.add(cat);
          }
        }
        parsed = parsed.copyWith(homeCategories: current);
        box.put(key, parsed.toMap());
      } else if (schemaVersion < AppSettings.schemaVersion) {
        box.put(key, parsed.toMap());
      }
      return parsed;
    }
    return AppSettings.defaults;
  }

  Future<void> saveSettings(AppSettings settings, {int? updatedAtMs}) async {
    final box = _boxOrNull ?? await Hive.openBox<dynamic>(boxName);
    await box.put(key, settings.toMap());
    final timestamp = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    await box.put('settings_updated_at_ms', timestamp);
  }

  int getSettingsUpdatedAtMs() {
    final box = _boxOrNull;
    if (box == null) return 0;
    return (box.get('settings_updated_at_ms') as int?) ?? 0;
  }
}
