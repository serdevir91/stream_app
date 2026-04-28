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
          backendUrl: 'http://127.0.0.1:8000',
          autoSelectSource: true,
          preferredSourceId: '',
        );
        box.put(key, migrated.toMap());
        return migrated;
      }

      final parsed = AppSettings.fromMap(raw);
      if (schemaVersion < AppSettings.schemaVersion) {
        box.put(key, parsed.toMap());
      }
      return parsed;
    }
    return AppSettings.defaults;
  }

  Future<void> saveSettings(AppSettings settings) async {
    final box = _boxOrNull ?? await Hive.openBox<dynamic>(boxName);
    await box.put(key, settings.toMap());
  }
}
