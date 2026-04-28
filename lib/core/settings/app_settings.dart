class AppSettings {
  static const int schemaVersion = 3;

  final String appLanguage;
  final String subtitleLanguage;
  final String tmdbAccessToken;
  final String backendUrl;
  final bool autoSelectSource;
  final String preferredSourceId;

  const AppSettings({
    required this.appLanguage,
    required this.subtitleLanguage,
    required this.tmdbAccessToken,
    required this.backendUrl,
    required this.autoSelectSource,
    required this.preferredSourceId,
  });

  static const AppSettings defaults = AppSettings(
    appLanguage: 'en',
    subtitleLanguage: 'en',
    tmdbAccessToken: '',
    backendUrl: 'http://127.0.0.1:8000',
    autoSelectSource: true,
    preferredSourceId: '',
  );

  AppSettings copyWith({
    String? appLanguage,
    String? subtitleLanguage,
    String? tmdbAccessToken,
    String? backendUrl,
    bool? autoSelectSource,
    String? preferredSourceId,
  }) {
    return AppSettings(
      appLanguage: appLanguage ?? this.appLanguage,
      subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
      tmdbAccessToken: tmdbAccessToken ?? this.tmdbAccessToken,
      backendUrl: backendUrl ?? this.backendUrl,
      autoSelectSource: autoSelectSource ?? this.autoSelectSource,
      preferredSourceId: preferredSourceId ?? this.preferredSourceId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'schemaVersion': schemaVersion,
      'appLanguage': appLanguage,
      'subtitleLanguage': subtitleLanguage,
      'tmdbAccessToken': tmdbAccessToken,
      'backendUrl': backendUrl,
      'autoSelectSource': autoSelectSource,
      'preferredSourceId': preferredSourceId,
    };
  }

  factory AppSettings.fromMap(Map<dynamic, dynamic> map) {
    return AppSettings(
      appLanguage: (map['appLanguage'] ?? 'en').toString(),
      subtitleLanguage: (map['subtitleLanguage'] ?? 'en').toString(),
      tmdbAccessToken: (map['tmdbAccessToken'] ?? '').toString(),
      backendUrl: (map['backendUrl'] ?? 'http://127.0.0.1:8000').toString(),
      autoSelectSource: (map['autoSelectSource'] ?? true) == true,
      preferredSourceId: (map['preferredSourceId'] ?? '').toString(),
    );
  }
}

const Map<String, String> supportedAppLanguages = {
  'tr': 'Turkce',
  'en': 'English',
};

const Map<String, String> supportedSubtitleLanguages = {
  'tr': 'Turkce',
  'en': 'English',
  'es': 'Espanol',
  'de': 'Deutsch',
  'fr': 'Francais',
  'it': 'Italiano',
  'pt': 'Portugues',
  'ru': 'Russian',
  'ar': 'Arabic',
};
